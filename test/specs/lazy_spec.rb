require 'minitest/autorun'

describe Zoidberg::Lazy do

  it 'should require a block be provided' do
    ->{ Zoidberg::Lazy.new }.must_raise ArgumentError
  end

  it 'should pretend to be given class' do
    lazy = Zoidberg::Lazy.new(String){ 1 }
    lazy.is_a?(String).must_equal true
  end

  it 'should provide the instance within block' do
    lazy = Zoidberg::Lazy.new{ 1 }
    lazy.must_equal 1
  end

  it 'should wait for value to be available' do
    @value = nil
    Thread.new{ sleep(2.1); @value = :ohai }
    lazy = Zoidberg::Lazy.new{ @value }
    start = Time.now.to_f
    lazy.must_equal :ohai
    (Time.now.to_f - start).must_be :>, 2
  end

end
