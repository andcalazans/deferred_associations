require 'spec_helper'

describe 'has_many_with_deferred_save' do
  before :each do
    @room    = Room.create(maximum_occupancy: 2)
    @table1  = Table.create(room_id: @room.id)
    @table2  = Table.create
    @chair1  = Chair.create(table_id: @table1.id, name: 'First')
    @chair2  = Chair.create(table_id: @table2.id, name: 'Second')
  end

  it 'should work with tables obj setter/getter' do
    expect(@room.tables).to eq [@table1]
    @room.tables = [@table1, @table2]
    expect(Room.find(@room.id).tables).to eq([@table1]) # not saved yet
    expect(@room.tables).to eq([@table1, @table2])
    expect(@room.table_ids).to eq([@table1.id, @table2.id])
    expect(@room.save).to be true
    expect(Room.find(@room.id).tables).to eq([@table1, @table2])
  end

  it 'should work with tables obj setter/getter, used twice' do
    expect(@room.tables).to eq([@table1])
    @room.tables = [@table1]
    @room.tables = [@table1, @table2]
    expect(Room.find(@room.id).tables).to eq([@table1]) # not saved yet
    expect(@room.table_ids).to eq([@table1.id, @table2.id])
    expect(@room.tables).to eq([@table1, @table2])
    expect(@room.save).to be true
    expect(Room.find(@room.id).tables).to eq([@table1, @table2])
  end

  it 'should work with tables id setter/getter' do
    expect(@room.table_ids).to eq([@table1.id])
    @room.table_ids = [@table1.id, @table2.id]
    expect(Room.find(@room.id).table_ids).to eq([@table1.id]) # not saved yet
    expect(@room.save).to be true
    expect(Room.find(@room.id).table_ids).to eq([@table1.id, @table2.id])
  end

  it 'should work with tables id setter/getter, used twice' do
    expect(@room.table_ids).to eq([@table1.id])
    @room.table_ids = [@table1.id]
    @room.table_ids = [@table1.id, @table2.id]
    expect(Room.find(@room.id).table_ids).to eq([@table1.id]) # not saved yet
    expect(@room.save).to be true
    expect(Room.find(@room.id).table_ids).to eq([@table1.id, @table2.id])
  end

  it 'should work with array methods' do
    expect(@room.tables).to eq([@table1])
    @room.tables << @table2
    expect(Room.find(@room.id).tables).to eq([@table1]) # not saved yet
    expect(@room.save).to be true
    expect(Room.find(@room.id).tables).to eq([@table1, @table2])
    @room.tables -= [@table1]
    expect(Room.find(@room.id).tables).to eq([@table1, @table2])
    expect(@room.save).to be true
    expect(Room.find(@room.id).tables).to eq([@table2])
  end

  it 'should reload temporary objects' do
    @room.tables << @table2
    expect(@room.tables).to eq([@table1, @table2])
    @room.reload
    expect(@room.tables).to eq([@table1])
  end

  it 'should be dumpable with Marshal' do
    expect { Marshal.dump(@room.tables) }.not_to raise_exception
    expect { Marshal.dump(Room.new.tables) }.not_to raise_exception
  end

  describe 'with through option' do
    it 'should have a correct list' do
      # TODO: these testcases need to be improved
      expect(@room.chairs).to eq([@chair1]) # through table1
      @room.tables << @table2
      expect(@room.save).to be true
      expect(@room.chairs).to eq([@chair1]) # association doesn't reload itself
      @room.reload
      expect(@room.chairs).to eq([@chair1, @chair2])
    end

    it 'should defer association methods' do
      expect(@room.chairs.first).to eq(@chair1)
      if ar4?
        expect(@room.chairs.where(name: 'First')).to eq([@chair1])
      else
        expect(@room.chairs.find(:all, conditions: { name: 'First' })).to eq([@chair1])
      end

      expect do
        @room.chairs.create(name: 'New one')
      end.to raise_error(ActiveRecord::HasManyThroughCantAssociateThroughHasOneOrManyReflection)
    end

    it 'should be dumpable with Marshal' do
      expect { Marshal.dump(@room.chairs) }.not_to raise_exception
      expect { Marshal.dump(Room.new.chairs) }.not_to raise_exception
    end
  end

  describe 'with autosave option' do
    before :all do
      @now = Time.now
      @table3 = Table.create(name: 'Table3', room_id: Room.create(name: 'Kitchen', updated_at: @now - 5.minutes).id)
      @table4 = Table.create(name: 'Table4', room_id: Room.create(name: 'Dining room', updated_at: @now - 5.minutes).id)
      @windows = [Window.create(name: 'South'), Window.create(name: 'West'), Window.create(name: 'East')]
    end

    it 'saves windows of associated room, if table gets saved' do
      expect(Time).to receive(:now).and_return(@now - 2.minutes).at_least(1)

      @table3.room_with_autosave.windows = [@windows.first, @windows.second]
      @table4.room_with_autosave.window_ids = [@windows.third.id]

      expect(@table3.room_with_autosave).to be_changed
      expect(@table4.room_with_autosave).to be_changed
      expect(@table3.room_with_autosave.changes.include?('windows')).to be true
      expect(@table4.room_with_autosave.changes.include?('windows')).to be true

      @table3.save!
      @table4.save!

      expect(@table3.room.windows).to eq [@windows.first, @windows.second]
      expect(@table4.room.windows).to eq [@windows.third]
      expect(@table3.room.updated_at).to eq @now - 2.minutes
      expect(@table4.room.updated_at).to eq @now - 2.minutes
    end

    it 'does not set changed or updated_at, if nothing changed' do
      expect(Time).to receive(:now).and_return(@now - 1.minutes).at_least(1)

      @table3.room_with_autosave.reload
      @table4.room_with_autosave.reload

      # same as above
      @table3.room_with_autosave.windows = [@windows.first, @windows.second]
      @table4.room_with_autosave.window_ids = [@windows.third.id]

      expect(@table3.room_with_autosave).not_to be_changed
      expect(@table4.room_with_autosave).not_to be_changed
      @table3.save!
      @table4.save!
      expect(@table3.room.windows).to eq [@windows.first, @windows.second]
      expect(@table4.room.windows).to eq [@windows.third]
      expect(@table3.room.updated_at).to eq @now - 2.minutes # still the same
      expect(@table4.room.updated_at).to eq @now - 2.minutes
    end

    it 'does change however, if the sorting changed' do
      # This might be unexpected, but we don't want to clutter our code with to much array comparison code
      # This test is here to document the existing code.
      expect(Time).to receive(:now).and_return(@now - 1.minutes).at_least(1)

      @table3.room_with_autosave.reload
      @table3.room_with_autosave.windows = [@windows.second, @windows.first]

      expect(@table3.room_with_autosave).to be_changed
      @table3.save!
      @table3.room.reload
      expect(@table3.room.windows).to eq [@windows.first, @windows.second]
      expect(@table3.room.updated_at).to eq @now - 1.minutes
    end
  end
end
