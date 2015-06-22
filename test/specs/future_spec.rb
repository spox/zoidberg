require 'minitest/autorun'

describe Zoidberg::Future do

  let(:future){ Zoidberg::Future }

  it 'should execute block and return value' do
    future.new{ :ohai }.value.must_equal :ohai
  end

  it 'should allow getting multiple values' do
    f = future.new{ :ohai }
    f.value.must_equal :ohai
    f.value.must_equal :ohai
  end

  it 'should wait for value when requested' do
    future.new{ sleep(1); :ohai }.value.must_equal :ohai
  end

  it 'should allow checking if value is available' do
    f = future.new{ sleep(1); :ohai }
    f.available?.must_equal false
    f.value.must_equal :ohai
    f.available?.must_equal true
  end

end
