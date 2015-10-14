# Zoidberg

> Why not Zoidberg?

## About

Zoidberg does a couple things. First, it can be a simple way to
provide implicit synchronization for thread safety in existing
code that is otherwise unsafe. Second, it can provide supervision
and pooling. This library is heavily inspired by Celluloid but,
while some APIs may look familiar, they do not share a familiar
implementation.

## Usage

Zoidberg provides a `Shell` which can be loaded into a class. After
it has been loaded, new instances will provide implicit synchronization,
which is nifty. For example, lets take a simple `Fubar` class that does
a simple thing:

```ruby
class Fubar

  attr_reader :string

  def initialize
    @string = ''
    @chars = []
  end

  def append
    string << char
  end

  private

  def char
    if(@chars.empty?)
      @chars.replace (A..Z).to_a
    end
    @chars.shift
  end

end
```

Pretty simple class whose only purpose is to add characters to a string.
And it does just that:

```ruby
inst = Fubar.new
20.times{ inst.append }
inst.string

# => "ABCDEFGHIJKLMNOPQRST"
```

So this does exactly what we expect it to. Now, lets update this example and
toss some threads into the mix:

```ruby
inst = Fubar.new
20.times.map{ Thread.new{ inst.append } }.map(&:join)
inst.string

# => "ABCDEFGHIJKLMNOPQRST"
```

Cool, we get the same results! Looks like everything is great. Lets run it
again to bask in this multi-threaded awesomeness!

```ruby
# => "AABCDEFGHIJKLMNOPQRS"
```

Hrm, that doesn't look quite right. It looks like there's an extra 'A' at the start. Maybe
everything isn't so great. Lets try a few more:

```ruby
inst = Fubar.new
100.times.map do
  20.times.map{ Thread.new{ inst.append } }.map(&:join)
end.uniq

# => ["ABCDEFGHIJKLMNOPQRST", "ABCDEDGHIJKLMNOPQRST", "ACDEFGHIJKLMNOPQRST", "BCDEFGHIJKLMNOPQRST", "AABCDEFGHIJKLMNOPQRS", "ABCDEFHGIJKLMNOPQRST"]
```

Whelp, I don't even know what that is supposed to be, but it's certainly
not what we are expecting. Well, we _are_ expecting it because this is
an example on synchronization, but lets just pretend at this point we are
amazed at this turn of events.

To fix this, we need to add some synchronization so multiple threads aren't
attempting to mutate state at the same time. But, instead of modifying the
class and explicitly adding synchronization, lets see what happens when
we toss `Zoidberg::Shell` into the mix (cause it's why everyone is here
in the first place). We can just continue on with our previous examples
and open up our defined class to inject the shell and re-run the example:

```ruby
require 'zoidberg'

class Fubar
  include Zoidberg::Shell
end

inst = Fubar.new
20.times.map{ Thread.new{ inst.append } }.map(&:join)
inst.string

# => "ABCDEFGHIJKLMNOPQRST"
```

and running it lots of times we get:

```ruby
100.times.map{20.times.map{ Thread.new{ inst.append } }.map(&:join)}.uniq

# => ["ABCDEFGHIJKLMNOPQRST"]
```

So this is pretty neat. We had a class that was shown to not be thread
safe. We tossed a module into that class. Now that class is thread safe.

### Should I really do this?

Maybe?

## Features

Originally, we looked at just adding safety but this library provides
a handful more of things.

### Implicit Locking

Zoidberg automatically synchronizes requests made to an instance. This
behavior can be short circuited if the actual instance creates a thread
and calls a method on itself. Otherwise, all external access to the
instance will be automatically synchronized. Nifty.

This synchronization behavior comes from the shells included within
Zoidberg. There are two styles of shells available:

#### `Zoidberg::SoftShell`

This is the default shell used when the generic `Zoidberg::Shell` module
is included. It will wrap the raw instance and synchronize requests to
the instance.

#### `Zoidberg::HardShell`

This shell is still in development and not fully supported yet. The
hard shell is an implementation that is more reflective of the actor
model with a single thread wrapping an instance and synchronizing access.

### Garbage Collection

Garbage collection happens as usual with Zoidberg. When an instance is created
the result may look like the instance but really it is a proxy wrapping the
raw instance. When the proxy falls out of scope and is garbage collected the
raw instance it wrapped will also fall out of scope and be garbage collected.
This wrapping behavior is what allows supervised instances to be automatically
swapped out on failure state without requiring intervention. It also introduces
the ability to add support for destructors, which is pretty cool.

#### Destructors

Instances can define destructors via the `#terminate` method. When the instance
is garbage collected, the `#terminate` method will be called prior to the instance
falling out of scope and being removed from the system. This allows the introduction
of destructors:

```ruby

class Fubar
  include Zoidberg::Shell

  ...

  def terminate
    puts "I am being garbage collected!"
  end
end
```

### Signals

Simple signals are available as well as signals pushing data.

#### Simple Signals

```ruby
sig = Zoidberg::Signal.new
Thread.new do
  sig.wait(:go)
  puts 'Done!'
end
puts 'Ready to signal!'
sleep(1)
sig.signal(:go)
puts 'Signal sent'
```

#### Simple Broadcasting

```ruby
sig = Zoidberg::Signal.new
5.times do
  Thread.new do
    sig.wait(:go)
    puts 'Done!'
  end
end
puts 'Ready to signal!'
sleep(1)
sig.broadcast(:go)
puts 'Broadcast sent'
```

#### Pushing data

```ruby
sig = Zoidberg::Signal.new
Thread.new do
  value = sig.wait(:go)
  puts "Done! Received: #{value.inspect}"
end
puts 'Ready to signal!'
sleep(1)
sig.signal(:go, :ohai)
puts 'Signal sent'
```

### Supervision

Zoidberg can provide instance supervision. To enable supervision on a
class, include the module:

```ruby

class Fubar
  include Zoidberg::Supervise
end
```

This will implicitly load the `Zoidberg::Shell` module and new instances
will be supervised. Supervision means Zoidberg will watch for unexpected
exceptions. What are "unexpected exceptions"? They are any exception raised
via `raise`. This will cause the instance to be torn down and a new instance
to be instantiated. To the outside observer, nothing will change and no
modification is required.

### Pools

Zoidberg allows pooling lazy supervised instances. Unexpected failures will
cause the instance to be terminated and re-initialized as usual. The pool
will deliver requests to free instances, or queue them until a free instance
is available.
