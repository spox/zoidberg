require_relative '../helper'

describe Zoidberg::Signal do

  let(:signal){ Zoidberg::Signal }

  it 'should return false when no waiters are signaled' do
    signal.new.signal(:fubar).must_equal false
  end

  it 'should return false when no waiters are broadcasted' do
    signal.new.broadcast(:fubar).must_equal false
  end

  it 'should signal a single waiter' do
    sig = signal.new
    t1 = Thread.new{ sig.wait_for(:go) }
    t2 = Thread.new{ sig.wait_for(:go) }

    sleep(0.01) # let waiters setup

    sig.signal(:go).must_equal true # confirms we have waiters

    sleep(0.01) # let signal process

    status = [t1.alive?, t2.alive?]
    status.must_include true
    status.must_include false
  end

  it 'should broadcast to all waiters' do
    sig = signal.new
    t1 = Thread.new{ sig.wait_for(:go) }
    t2 = Thread.new{ sig.wait_for(:go) }

    sleep(0.01) # let waiters setup

    sig.broadcast(:go).must_equal true # confirms we have waiters

    sleep(0.01) # let signal process

    status = [t1.alive?, t2.alive?]
    status.all?{|s| s == false}.must_equal true
  end

  it 'should provide time spent waiting for signal' do
    sig = signal.new
    Thread.new do
      sleep 2
      sig.signal(:go)
    end
    result = sig.wait_for(:go)
    result.must_be :>=, 2
    result.must_be_kind_of Float
  end

  it 'should allow sending data on signal' do
    sig = signal.new
    Thread.new do
      sleep(0.1)
      sig.signal(:go, :ohai)
    end
    result = sig.wait_for(:go)
    result.must_equal :ohai
  end

  it 'should allow sending data on broadcast' do
    sig = signal.new
    result = Queue.new
    2.times do
      Thread.new do
        result.push sig.wait_for(:go)
      end
    end
    sleep(0.1)
    sig.broadcast(:go, :ohai)
    sleep(0.1)
    result.size.must_equal 2
    result.pop.must_equal :ohai
    result.pop.must_equal :ohai
  end

end
