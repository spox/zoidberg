require 'minitest/autorun'

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
      end
      c
    end

    it 'should build a new proxy instance' do
      inst = klass.new
      inst._zoidberg_object.wont_be_nil
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
      ->{ inst.something_useful }.must_raise Zoidberg::Supervise::DeadException
    end

  end

end
