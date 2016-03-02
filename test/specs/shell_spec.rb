require_relative '../helper'

describe Zoidberg::Shell do

  describe 'module inclusion' do

    it 'should add class and instance methods on inclusion' do
      klass = Class.new
      klass.class_eval do
        include Zoidberg::Shell
      end
      klass.respond_to?(:unshelled_new).must_equal true
      klass.public_instance_methods.must_include :_zoidberg_proxy
      klass.new.wont_be_nil
    end

    it 'should handle multiple inclusions' do
      klass = Class.new
      klass.class_eval do
        include Zoidberg::Shell
        include Zoidberg::Shell
        include Zoidberg::Shell
      end
      klass.respond_to?(:unshelled_new).must_equal true
      klass.public_instance_methods.must_include :_zoidberg_proxy
      klass.new.wont_be_nil
    end

  end

  describe 'basic instance behavior' do

    let(:klass) do
      c = Class.new
      c.class_eval do
        include Zoidberg::Shell
        def initialize
          @queue = Queue.new
        end
        def pause
          @queue.pop
        end
        def go
          @queue.push :ohai
        end
        def me
          self
        end
        def wrapped_me
          current_self
        end
      end
      c
    end

    it 'should build a new proxy instance' do
      inst = klass.new
      inst._zoidberg_object.wont_be_nil
    end

    it 'should provided wrapped and unwrapped self' do
      inst = klass.new
      inst.me.wont_equal inst.wrapped_me
    end

    it 'should behave like a normal instance' do
      inst = klass.new
      inst.go
      inst.pause.must_equal :ohai
    end

    it 'should only allow one thread into the instance' do
      inst = klass.new
      t_pause = Thread.new{ inst.pause }
      t_go = Thread.new{ sleep(0.01); inst.go }
      sleep(0.1) # let threads setup
      t_pause.alive?.must_equal true
      t_go.alive?.must_equal true
    end

    it 'should flag when instance is locked' do
      inst = klass.new
      t_pause = Thread.new{ inst.pause }
      sleep(0.01)
      inst._zoidberg_locked?.must_equal true
      inst._zoidberg_available?.must_equal false
    end

    it 'should raise correct exception' do
      inst = klass.new
      ->{ inst.fubar }.must_raise NoMethodError
    end

  end

  describe 'threaded usage' do

    let(:klass) do
      c = Class.new
      c.class_eval do
        include Zoidberg::Shell
        def initialize
          @queue = Queue.new
        end
        def pause
          defer{ @queue.pop }
        end
        def go
          @queue.push :ohai
        end
        def wait
          sleep 0.1
        end
      end
      c
    end

    it 'should not be locked when defer is used' do
      inst = klass.new
      t_pause = Thread.new{ inst.pause }
      sleep(0.01)
      inst._zoidberg_locked?.must_equal false
      inst.go
      sleep(0.01)
      t_pause.alive?.must_equal false
    end

    it 'should automatically defer when sleeping' do
      inst = klass.new
      inst.wait
      sleep(0.01)
      inst._zoidberg_locked?.must_equal false
    end

  end

  describe 'async behavior' do

    let(:klass) do
      Class.new do
        include Zoidberg::Shell
        def act_busy
          loop{ ::Kernel.sleep(1) }
        end
        def something_useful
          :ohai
        end
      end
    end

    it 'should act busy when busy' do
      inst = klass.new
      t = Thread.new{ inst.act_busy }
      sleep(0.01)
      inst._zoidberg_available?.must_equal false
    end

    it 'should act busy when locked async busy' do
      inst = klass.new
      inst.async(:locked).act_busy
      sleep(0.01)
      inst._zoidberg_available?.must_equal false
    end

    it 'should not act busy when unlocked async busy' do
      inst = klass.new
      inst.async.act_busy
      sleep(0.01)
      inst._zoidberg_available?.must_equal true
    end

  end

  describe 'instance destruction' do

    let(:klass) do
      Class.new do
        include Zoidberg::Shell

        def something_useful
          :ohai
        end
      end
    end

    it 'should render instance useless on destruction' do
      inst = klass.new
      inst.something_useful.must_equal :ohai
      inst._zoidberg_destroy!
      ->{ inst.something_useful }.must_raise Zoidberg::DeadException
    end

  end

  describe 'garbage collection' do

    let(:klass) do
      Class.new do
        include Zoidberg::Shell

        def something_useful
          :ohai
        end
      end
    end

    it 'should not really be the object it claims to be' do
      inst = klass.new
      inst.__id__.wont_equal inst.object_id
    end

    it 'should keep a register of itself' do
      inst = klass.new
      Zoidberg::Proxy.registry[inst.__id__].wont_be_nil
      Zoidberg::Proxy.registry[inst.__id__]._zoidberg_available?.wont_be_nil
    end

    it 'should properly unregister itself' do
      inst = klass.new
      o_id = inst.__id__
      Zoidberg::Proxy.registry[o_id].wont_be_nil
      inst = nil
      GC.start
      sleep(0.01)
      GC.start
      sleep(0.01)
      Zoidberg::Proxy.registry[o_id].must_be_nil
    end

    it 'should destroy real instance when unregistering' do
      inst = klass.new
      o_id = inst.__id__
      Zoidberg::Proxy.registry[o_id].wont_be_nil
      obj = inst._raw_instance
      obj.something_useful.must_equal :ohai
      inst = nil
      ObjectSpace.garbage_collect
      sleep(0.02)
      Zoidberg::Proxy.registry[o_id].must_be_nil
      ->{ obj.something_useful }.must_raise Zoidberg::DeadException
    end

  end

  describe 'linking instances' do

    let(:watcher) do
      Class.new do
        include Zoidberg::Shell

        trap_exit :handle_error
        attr_reader :instance, :error
        def handle_error(instance, error)
          @instance = instance
          @error = error
        end

        def something_useful
          :ohai
        end
      end
    end

    let(:boomer) do
      Class.new do
        include Zoidberg::Shell

        def something_useful
          :ohai
        end

        def something_not_useful
          raise 'ACK'
        end
      end
    end

    it 'should allow linking instances' do
      watch = watcher.new
      boom = boomer.new
      watch.link boom
    end

    it 'should execute linkage on error when not supervised' do
      watch = watcher.new
      boom = boomer.new
      watch.link boom
      ->{ boom.something_not_useful }.must_raise RuntimeError
      sleep(0.1)
      watch.instance.wont_be_nil
      watch.error.wont_be_nil
    end

  end

end
