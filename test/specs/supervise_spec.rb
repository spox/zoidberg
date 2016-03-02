require_relative '../helper'

describe Zoidberg::Supervise do

  it 'should automatically load Zoidberg::Shell' do
    c = Class.new
    c.class_eval{ include Zoidberg::Supervise }
    c.ancestors.must_include Zoidberg::Shell::InstanceMethods
  end

  it 'should handle multiple loads' do
    c = Class.new
    c.class_eval do
      include Zoidberg::Supervise
      include Zoidberg::Supervise
      include Zoidberg::Supervise
    end
    c.new.wont_be_nil
  end

  describe 'supervised generic instance' do

    let(:klass) do
      c = Class.new
      c.class_eval do
        include Zoidberg::Supervise
        def snipe
          raise 'AHHHHHHH'
        end
        def halted_snipe
          begin
            raise 'AHHHHHHH'
          rescue => e
            abort e
          end
        end
      end
      c
    end

    it 'should create a new instance as normal' do
      klass.new.must_be_kind_of klass
    end

    it 'should rebuild instance on unexpected exception' do
      inst = klass.new
      o_id = inst._raw_instance.object_id
      ->{ inst.snipe }.must_raise RuntimeError
      sleep(0.01)
      inst._raw_instance.object_id.wont_equal o_id
    end

    it 'should not rebuild instance on expected exception' do
      inst = klass.new
      o_id = inst._raw_instance.object_id
      ->{ inst.halted_snipe }.must_raise RuntimeError
      inst._raw_instance.object_id.must_equal o_id
    end

  end

  describe 'supervised customized instance' do

    before{ $terminated_log = Hash.new }

    let(:klass) do
      c = Class.new
      c.class_eval do
        include Zoidberg::Supervise
        def snipe
          raise 'AHHHHHHH'
        end
        def halted_snipe
          begin
            raise 'AHHHHHHH'
          rescue => e
            abort e
          end
        end
      end
      c
    end

    let(:klass_with_restart) do
      c = klass.dup
      c.class_eval do
        attr_reader :restarted
        def restart(error)
          @restarted = true
        end
      end
      c
    end

    let(:klass_with_restarted) do
      c = klass.dup
      c.class_eval do
        attr_reader :restarted
        def restarted!
          @restarted = true
        end
      end
      c
    end

    let(:klass_with_terminate) do
      c = klass.dup
      c.class_eval do
        attr_reader :terminated
        def terminate
          $terminated_log[object_id] = true
        end
      end
      c
    end

    let(:klass_with_restart_and_terminate) do
      c = klass.dup
      c.class_eval do
        attr_reader :restarted
        attr_reader :terminated
        def restart(error)
          @restarted = true
        end
        def terminate
          $terminated_log[object_id] = true
        end
      end
      c
    end

    it 'should call restart when provided on instance' do
      inst = klass_with_restart.new
      obj_id = inst.object_id
      ->{ inst.snipe }.must_raise RuntimeError
      sleep(0.01)
      inst.object_id.must_equal obj_id
      inst.restarted.must_equal true
    end

    it 'should call terminate when provided on instance' do
      inst = klass_with_terminate.new
      obj_id = inst._raw_instance.object_id
      ->{ inst.snipe }.must_raise RuntimeError
      sleep(0.01)
      inst._raw_instance.object_id.wont_equal obj_id
      $terminated_log[obj_id].must_equal true
    end

    it 'should call restart and not terminate when provided on instance' do
      inst = klass_with_restart_and_terminate.new
      obj_id = inst.object_id
      ->{ inst.snipe }.must_raise RuntimeError
      sleep(0.01)
      inst.object_id.must_equal obj_id
      inst.restarted.must_equal true
      $terminated_log[obj_id].wont_equal true
    end

    it 'should call restarted on new instance after replacement' do
      inst = klass_with_restarted.new
      obj_id = inst.object_id
      ->{ inst.snipe }.must_raise RuntimeError
      sleep(0.01)
      inst.object_id.wont_equal obj_id
      inst.restarted.must_equal true
    end

  end

end
