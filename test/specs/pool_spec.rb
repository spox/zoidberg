require 'minitest/autorun'

describe Zoidberg::Pool do

  let(:worker) do
    c = Class.new
    c.class_eval do
      include Zoidberg::Supervise
      def snipe
        raise 'AHHHHHHHHHHH'
      end
      def ohai
        :ohai
      end
    end
    c
  end

  let(:pool){ Zoidberg::Pool.new(worker) }

  it 'should require supervised workers' do
    ->{ Zoidberg::Pool.new(String) }.must_raise TypeError
    Zoidberg::Pool.new(worker).must_be_kind_of Zoidberg::Pool
  end

  it 'should provide one worker by default' do
    pool._workers.size.must_equal 1
    pool._worker_count.must_equal 1
  end

  it 'should proxy to single worker' do
    pool.ohai.must_equal :ohai
  end

  it 'should grow pool when requested' do
    pool._workers.count.must_equal 1
    pool._worker_count.must_equal 1
    pool._worker_count 3
    pool._worker_count.must_equal 3
    pool._workers.count.must_equal 3
  end

  it 'should shrink pool when requested' do
    pool._workers.count.must_equal 1
    pool._worker_count.must_equal 1
    pool._worker_count 3
    pool._worker_count.must_equal 3
    pool._workers.count.must_equal 3
    pool._worker_count 2
    pool._worker_count.must_equal 2
    pool._workers.count.must_equal 2
  end

  it 'should still have worker if worker dies' do
    o_id = pool._workers.first._raw_instance.object_id
    pool._workers.first._raw_instance.object_id.must_equal o_id
    ->{ pool.snipe }.must_raise RuntimeError
    pool._workers.size.must_equal 1
    pool._workers.first._raw_instance.object_id.wont_equal o_id
  end

  it 'should process all requests' do
    pool._worker_count 5
    pool._workers.size.must_equal 5
    threads = 100.times.map do
      Thread.new{ pool.ohai }
    end
    threads.map(&:alive?).must_include true
    sleep(1)
    threads.map(&:alive?).wont_include true
  end

end
