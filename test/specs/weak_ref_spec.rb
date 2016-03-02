require_relative '../helper'

describe Zoidberg::WeakRef do

  let(:weakref){ Zoidberg::WeakRef }

  it 'should act like the thing it references' do
    thing = 'ohai'
    ref = weakref.new(thing)
    ref.must_equal thing
    ref.object_id.must_equal thing.object_id
  end

  it 'should not be the thing it references' do
    thing = 'ohai'
    ref = weakref.new(thing)
    ref.__id__.wont_equal thing.__id__
  end

  it 'should allow the thing it references to be garbage collected' do
    thing = 'ohai'
    ref = weakref.new(thing)
    thing = nil
    ObjectSpace.garbage_collect
    sleep(0.02)
    ->{ ref.chars }.must_raise Zoidberg::WeakRef::RecycledException
  end

end
