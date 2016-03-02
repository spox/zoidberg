require_relative '../helper'

describe Zoidberg::Timer do

  before do
    @timer = Zoidberg::Timer.new
  end

  after do
    @timer.terminate
  end

  let(:timer){ @timer }

  it 'should run action after interval' do
    value = false
    timer.after(0.01){ value = true }
    sleep(0.1)
    value.must_equal true
  end

  it 'should run action multiple times' do
    value = 0
    timer.every(0.1){ value += 1 }
    sleep(1.05)
    value.must_equal 10
  end

  it 'should allow pausing actions' do
    value = 0
    timer.every(0.1){ value += 1 }
    sleep(0.25)
    timer.pause
    value.must_equal 2
    sleep(0.25)
    value.must_equal 2
  end

  it 'should allow resuming actions' do
    value = 0
    timer.every(0.1){ value += 1 }
    sleep(0.15)
    timer.pause
    value.must_equal 1
    sleep(0.25)
    value.must_equal 1
    timer.resume
    sleep(0.25)
    value.must_equal 4
  end

  it 'should allow cancelling actions' do
    value = 0
    timer.every(0.1){ value += 1 }
    sleep(0.15)
    timer.cancel
    value.must_equal 1
    sleep(0.2)
    value.must_equal 1
  end

end
