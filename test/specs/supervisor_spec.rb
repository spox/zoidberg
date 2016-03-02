require_relative '../helper'

describe Zoidberg::Supervisor do

  let(:klass) do
    Class.new do
      def foobar
        'fubar'
      end
      def die!
        raise 'ACK'
      end
    end
  end

  let(:klass_arg) do
    Class.new do
      attr_reader :arg
      def initialize(arg)
        @arg = arg
      end
    end
  end

  let(:klass_arg_block) do
    Class.new do
      attr_reader :arg
      attr_reader :blk
      def initialize(arg, &block)
        @arg = arg
        @blk = block
      end
    end
  end

  let(:klass_block) do
    Class.new do
      attr_reader :blk
      def initialize(&block)
        @blk = block
      end
    end
  end

  describe 'Instance supervision' do

    it 'should supervise an instance' do
      supervisor = Zoidberg::Supervisor.new
      supervisor.supervise_as :fubar, klass
      supervisor[:fubar].foobar.must_equal 'fubar'
    end

    it 'should rebuild supervised instance' do
      supervisor = Zoidberg::Supervisor.new
      supervisor.supervise_as :fubar, klass
      o_id = supervisor[:fubar]._raw_instance.object_id
      ->{ supervisor[:fubar].die! }.must_raise RuntimeError
      sleep(0.01)
      supervisor[:fubar]._raw_instance.object_id.wont_equal o_id
    end

    it 'should accept init argument' do
      supervisor = Zoidberg::Supervisor.new
      supervisor.supervise_as :fubar, klass_arg, 'fubar'
      supervisor[:fubar].arg.must_equal 'fubar'
    end

    it 'should accept init block' do
      supervisor = Zoidberg::Supervisor.new
      supervisor.supervise_as(:fubar, klass_block){ 'fubar' }
      supervisor[:fubar].blk.call.must_equal 'fubar'
    end

    it 'should accept init arg and block' do
      supervisor = Zoidberg::Supervisor.new
      supervisor.supervise_as(:fubar, klass_arg_block, 'foobar'){ 'fubar' }
      supervisor[:fubar].arg.must_equal 'foobar'
      supervisor[:fubar].blk.call.must_equal 'fubar'
    end

  end

  describe 'Pool supervision' do

    it 'should supervise a pool' do
      supervisor = Zoidberg::Supervisor.new
      supervisor.pool klass, :as => :fubar
      supervisor[:fubar].foobar.must_equal 'fubar'
      supervisor[:fubar]._worker_count.must_equal 1
    end

    it 'should supervise a multi-instance pool' do
      supervisor = Zoidberg::Supervisor.new
      supervisor.pool(klass, :as => :fubar, :size => 3)
      supervisor[:fubar].foobar.must_equal 'fubar'
      supervisor[:fubar]._worker_count.must_equal 3
    end

    it 'should accept init argument' do
      supervisor = Zoidberg::Supervisor.new
      supervisor.pool(klass_arg, :as => :fubar, :args => ['fubar'])
      supervisor[:fubar].arg.must_equal 'fubar'
    end

    it 'should accept init block' do
      supervisor = Zoidberg::Supervisor.new
      supervisor.pool(klass_block, :as => :fubar){ 'fubar' }
      supervisor[:fubar].blk.call.must_equal 'fubar'
    end

    it 'should accept init arg and block' do
      supervisor = Zoidberg::Supervisor.new
      supervisor.pool(klass_arg_block, :as => :fubar, :args => ['foobar']){ 'fubar' }
      supervisor[:fubar].arg.must_equal 'foobar'
      supervisor[:fubar].blk.call.must_equal 'fubar'
    end

  end

end
