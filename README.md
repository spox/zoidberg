# Zoidberg

> Why not Zoidberg?

## About

Zoidberg is a small library attempting to provide synchronization
and supervision without requiring any modifications to existing
implementations. It is heavily inspired by Celluloid and while some
APIs may look familiar they do not share a familiar implementation.

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

## Features

### Implicit Locking

Zoidberg automatically synchronizes requests made to an instance. This
behavior can be short circuited if the actual instance creates a thread
and calls a method on itself. Otherwise, all external access to the
instance will be automatically synchronized. Nifty.

### Supervision

Zoidberg provides lazy supervision. There is no single supervisor. Instead
supervision is handled by the proxy which wraps the class. Failure of an
instance will result in termination + reinstantiation. When externally
accessing the instance nothing requires modification.

### Pools

Zoidberg allows pooling lazy supervised instances. Unexpected failures will
cause the instance to be terminated and re-initialized as usual. The pool
will deliver requests to free instances, or queue them until a free instance
is available.

### Garbage Collection

Garbage collection happens as usual with Zoidberg. When an instance is created
the result may look like the instance but really it is proxy wrapping the
raw instance. When the proxy falls out of scope and is garbage collected the
raw instance it wrapped will also fall out of scope and be garbage collected.
