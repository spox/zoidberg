require 'minitest/autorun'

describe Zoidberg::Supervise do

  it 'should automatically load Zoidberg::Shell' do
    c = Class.new
    c.class_eval{ include Zoidberg::Supervise }
    c.ancestors.must_include Zoidberg::Supervise::InstanceMethods
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
      o_id = inst.object_id
      ->{ inst.snipe }.must_raise RuntimeError
      sleep(0.01)
      inst.object_id.wont_equal o_id
    end

    it 'should not rebuild instance on expected exception' do
      inst = klass.new
      o_id = inst.object_id
      ->{ inst.halted_snipe }.must_raise RuntimeError
      inst.object_id.must_equal o_id
    end

  end

end
