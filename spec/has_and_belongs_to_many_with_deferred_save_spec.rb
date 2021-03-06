require 'spec_helper'
require 'has_and_belongs_to_many_with_deferred_save'

describe 'has_and_belongs_to_many_with_deferred_save' do
  describe 'room maximum_occupancy' do
    before :all do
      @people = []
      @people << Person.create(name: 'Filbert')
      @people << Person.create(name: 'Miguel')
      @people << Person.create(name: 'Rainer')
      @room = Room.new(maximum_occupancy: 2)
    end
    after :all do
      Person.delete_all
      Room.delete_all
    end

    it 'passes initial checks' do
      expect(Room  .count).to eq(0)
      expect(Person.count).to eq(3)

      expect(@room.people).to eq([])
      expect(@room.people_without_deferred_save).to eq([])
      expect(@room.people_without_deferred_save.object_id).not_to eq(
        @room.unsaved_people.object_id
      )
    end

    it 'after adding people to room, it should not have saved anything to the database' do
      @room.people << @people[0]
      @room.people << @people[1]

      # Still not saved to the association table!
      expect(Room.count_by_sql('select count(*) from people_rooms')).to eq(0)
      expect(@room.people_without_deferred_save.size).               to eq(0)
    end

    it 'but room.people.size should still report the current size of 2' do
      expect(@room.people.size).to eq(2) # 2 because this looks at unsaved_people and not at the database
    end

    it 'after saving the model, the association should be saved in the join table' do
      @room.save # Only here is it actually saved to the association table!
      expect(@room.errors.full_messages).to eq([])
      expect(Room.count_by_sql('select count(*) from people_rooms')).to eq(2)
      expect(@room.people.size).                                     to eq(2)
      expect(@room.people_without_deferred_save.size).               to eq(2)
    end

    it 'when we try to add a 3rd person, it should add a validation error to the errors object like any other validation error' do
      expect { @room.people << @people[2] }.not_to raise_error
      expect(@room.people.size).       to eq(3)

      expect(Room.count_by_sql('select count(*) from people_rooms')).to eq(2)
      @room.valid?
      expect(@room.get_error(:people)).to eq('This room has reached its maximum occupancy')
      expect(@room.people.size).       to eq(3) # Just like with normal attributes that fail validation... the attribute still contains the invalid data but we refuse to save until it is changed to something that is *valid*.
    end

    it 'when we try to save, it should fail, because room.people is still invalid' do
      expect(@room.save).to eq(false)
      expect(Room.count_by_sql('select count(*) from people_rooms')).to eq(2) # It's still not there, because it didn't pass the validation.
      expect(@room.get_error(:people)).to eq('This room has reached its maximum occupancy')
      expect(@room.people.size).       to eq(3)
      expect(@people.map { |p| p.reload; p.rooms.size }).to eq([1, 1, 0])
    end

    it 'when we reload, it should go back to only having 2 people in the room' do
      @room.reload
      expect(@room.people.size).                                     to eq(2)
      expect(@room.people_without_deferred_save.size).               to eq(2)
      expect(@people.map { |p| p.reload; p.rooms.size }). to eq([1, 1, 0])
    end

    it 'if they try to go around our accessors and use the original accessors, then (and only then) will the exception be raised in before_adding_person...' do
      expect do
        @room.people_without_deferred_save << @people[2]
      end.to raise_error(RuntimeError)
    end

    it 'lets you bypass the validation on Room if we add the association from the other side (person.rooms <<)?' do
      @people[2].rooms << @room
      expect(@people[2].rooms.size).to eq(1)

      # Adding it from one direction does not add it to the other object's association (@room.people), so the validation passes.
      expect(@room.reload.people.size).to eq(2)
      @people[2].valid?
      expect(@people[2].errors.full_messages).to eq([])
      expect(@people[2].save).to eq(true)

      # It is only after reloading that @room.people has this 3rd object, causing it to be invalid, and by then it's too late to do anything about it.
      expect(@room.reload.people.size).to eq(3)
      expect(@room.valid?).to eq(false)
    end

    it 'only if you add the validation to both sides, can you ensure that the size of the association does not exceed some limit' do
      expect(@room.reload.people.size).to eq(3)
      @room.people.delete(@people[2])
      expect(@room.save).to eq(true)
      expect(@room.reload.people.size).to eq(2)
      expect(@people[2].reload.rooms.size).to eq(0)

      obj = @people[2]
      obj.do_extra_validation = true

      @people[2].rooms << @room
      expect(@people[2].rooms.size).to eq(1)

      expect(@room.reload.people.size).to eq(2)
      expect(@people[2].valid?).to be false
      expect(@people[2].get_error(:rooms)).to eq('This room has reached its maximum occupancy')
      expect(@room.reload.people.size).to eq(2)
    end

    it 'still lets you do find' do
      if ar4_or_more?
        expect(@room.people_without_deferring.where(name: 'Filbert').first).to eq(@people[0])
        expect(@room.people_without_deferred_save.where(name: 'Filbert').first).to eq(@people[0])
        expect(@room.people.where(name: 'Filbert').first).to eq(@people[0])
      else
        expect(@room.people_without_deferring.                     find(:first, conditions: { name: 'Filbert' })).to eq(@people[0])
        expect(@room.people_without_deferred_save.find(:first, conditions: { name: 'Filbert' })).to eq(@people[0])
        expect(@room.people_without_deferring.first(conditions: { name: 'Filbert' })).to eq(@people[0])
        expect(@room.people_without_deferred_save.first(conditions: { name: 'Filbert' })).to eq(@people[0])

        expect(@room.people.find(:first, conditions: { name: 'Filbert' })).to eq(@people[0])
        expect(@room.people.first(conditions: { name: 'Filbert' })).       to eq(@people[0])
        expect(@room.people.last(conditions: { name: 'Filbert' })).        to eq(@people[0])
      end

      expect(@room.people.first).                                        to eq(@people[0])
      expect(@room.people.last).                                         to eq(@people[1]) # @people[2] was removed before
      expect(@room.people.find_by_name('Filbert')).                      to eq(@people[0])
      expect(@room.people_without_deferred_save.find_by_name('Filbert')).to eq(@people[0])
    end

    it 'should be dumpable with Marshal' do
      expect { Marshal.dump(@room.people) }.not_to raise_exception
      expect { Marshal.dump(Room.new.people) }.not_to raise_exception
    end

    it 'should detect difference in association' do
      @room = Room.find(@room.id)
      expect(@room.bs_diff_before_module).to be_nil
      expect(@room.bs_diff_after_module).to  be_nil
      expect(@room.bs_diff_method).to        be_nil

      expect(@room.people.size).to eq(2)
      @room.people = [@room.people[0]]
      expect(@room.save).to be true

      expect(@room.bs_diff_before_module).to be true
      expect(@room.bs_diff_after_module).to  be true
      if ar2?
        expect(@room.bs_diff_method).to      be true
      else
        expect(@room.bs_diff_method).to      be_nil # Rails 3.2: nil (before_save filter is not supported)
      end
    end

    it 'should act like original habtm when using ID array with array manipulation' do
      @room = Room.find(@room.id)
      @room.people = [@people[0]]
      @room.save
      @room = Room.find(@room.id) # we don't want to let id and object setters interfere with each other
      @room.people_without_deferring_ids << @people[1].id

      if ar5_or_more?
        # In Rails 5, ID array manipulation is taken into account, but only temporarily,
        # therefore deferred_association doesn't mimic this behavior
        expect(@room.people_without_deferring_ids).to eq([@people[0].id, @people[1].id])
      else
        # ID array manipulation is ignored
        expect(@room.people_without_deferring_ids).to eq([@people[0].id])
      end

      expect(@room.person_ids.size).to eq(1)
      @room.person_ids << @people[1].id

      # deferred_association doesn't remember the additional ID, no matter, which AR version
      # we are in
      expect(@room.person_ids).to eq([@people[0].id])
      expect(Room.find(@room.id).person_ids).to eq([@people[0].id])
      expect(@room.save).to be true

      # Original association didn't save the temporarily saved changes,
      # the deferred association also looses the change on reload
      @room = Room.find(@room.id)
      expect(@room.people_without_deferring_ids).to eq([@people[0].id])
      expect(@room.person_ids).to eq([@people[0].id])
    end

    it 'should work with id setters' do
      @room = Room.find(@room.id)
      @room.people = [@people[0], @people[1]]
      @room.save
      @room = Room.find(@room.id)
      expect(@room.person_ids).to eq([@people[0].id, @people[1].id])
      @room.person_ids = [@people[1].id]
      expect(@room.person_ids).to eq([@people[1].id])
      expect(Room.find(@room.id).person_ids).to eq([@people[0].id, @people[1].id])
      expect(@room.save).to be true
      expect(Room.find(@room.id).person_ids).to eq([@people[1].id])
    end

    it 'should work with multiple id setters and object setters' do
      @room = Room.find(@room.id)
      @room.people     = [@people[0]]
      @room.person_ids = [@people[0].id, @people[1].id]
      @room.people     = [@people[1]]
      @room.person_ids = [@people[0].id, @people[1].id]
      @room.people     = [@people[1]]
      @room.save
      @room = Room.find(@room.id)
      expect(@room.people).to eq([@people[1]])
    end

    it 'should give klass in AR 3/4' do
      expect(@room.people.klass).to eq(Person) unless ar2?
    end

    it 'should give aliased_table_name in AR 2.3' do
      expect(@room.people.aliased_table_name).to eq('people') if ar2?
    end

    it 'should support reload both with and without params' do
      # find options are deprecated with AR 4, but reload still
      # supports them
      expect(@room.reload.id).to eq(@room.id)
      with_param = @room.reload(select: 'id')
      expect(with_param.id).to eq(@room.id)
    end
  end

  describe 'doors' do
    before :all do
      @rooms = []
      @rooms << Room.create(name: 'Kitchen',     maximum_occupancy: 1)
      @rooms << Room.create(name: 'Dining room', maximum_occupancy: 10)
      @door =   Door.new(name: 'Kitchen-Dining-room door')
    end

    it 'passes initial checks' do
      expect(Room.count).to eq(2)
      expect(Door.count).to eq(0)

      expect(@door.rooms).to eq([])
      expect(@door.rooms_without_deferred_save).to eq([])
    end

    it 'the association has an include? method' do
      @door.rooms << @rooms[0]
      expect(@door.rooms.include?(@rooms[0])).to be true
      expect(@door.rooms.include?(@rooms[1])).to be false
    end
  end
end
