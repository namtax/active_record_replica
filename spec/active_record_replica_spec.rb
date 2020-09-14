ENV['RAILS_ENV'] = 'test'

require 'pry'
require 'logger'
require 'erb'
require 'active_record'
require 'minitest/autorun'
require 'active_record_replica'
require 'awesome_print'

describe ActiveRecordReplica do 
  l                                 = Logger.new('test.log')
  l.level                           = ::Logger::DEBUG
  ActiveRecord::Base.logger         = l
  ActiveRecord::Base.configurations = YAML::load(ERB.new(IO.read('test/database.yml')).result)

  # Define Schema in second database (replica)
  # Note: This is not be required when the primary database is being replicated to the replica db
  ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations['test']['slave'])

  # Create table users in database active_record_replica_test
  ActiveRecord::Schema.define :version => 0 do
    create_table :users, :force => true do |t|
      t.string :name
      t.string :address
    end
  end

  # Define Schema in primary database
  ActiveRecord::Base.establish_connection(:test)

  # Create table users in database active_record_replica_test
  ActiveRecord::Schema.define :version => 0 do
    create_table :users, :force => true do |t|
      t.string :name
      t.string :address
    end
  end

  # AR Model
  class User < ActiveRecord::Base
    after_commit :replicate

    def replicate
      if ActiveRecord::Base.configurations['test']['slave']
        ActiveRecordReplica::Replica.connection.execute("insert into users (name, address) values ('#{name}', '#{address}')")
      end
    end
  end

  ActiveRecordReplica.install!(nil, 'test')
  ActiveRecord::Base.logger = Logger.new(STDOUT)

  describe 'the active_record_replica gem' do
    before do
      ActiveRecordReplica.ignore_transactions = false
      ActiveRecord::Base.establish_connection(:test)

      @name    = "Joe Bloggs"
      @address = "Somewhere"
    end

    # it 'saves to primary' do
    #   assert_equal true, @user.save!
    # end

    #
    # NOTE:
    #
    #   There is no automated replication between the SQL lite databases
    #   so the tests will be verifying that reads going to the "replica" (second)
    #   database do not find data written to the primary.
    #
    # it 'saves to primary, read from replica' do
    #   # Read from replica
    #   expect(User.where(:name => @name, :address => @address).count).to eq(0)

    #   # Write to primary
    #   expect(@user.save!).to be_truthy

    #   # Read from replica
    #   expect(User.where(:name => @name, :address => @address).count).to eq(0)
    # end

    # it 'save to primary, read from primary when in a transaction' do
    #   assert_equal false, ActiveRecordReplica.ignore_transactions?

    #   User.transaction do
    #     # The delete_all in setup should have cleared the table
    #     assert_equal 0, User.count

    #     # Read from Primary
    #     assert_equal 0, User.where(:name => @name, :address => @address).count

    #     # Write to primary
    #     assert_equal true, @user.save!

    #     # Read from Primary
    #     assert_equal 1, User.where(:name => @name, :address => @address).count
    #   end

    #   # Read from Non-replicated replica
    #   assert_equal 0, User.where(:name => @name, :address => @address).count
    # end

    # it 'save to primary, read from replica when ignoring transactions' do
    #   ActiveRecordReplica.ignore_transactions = true
    #   assert_equal true, ActiveRecordReplica.ignore_transactions?

    #   User.transaction do
    #     # The delete_all in setup should have cleared the table
    #     assert_equal 0, User.count

    #     # Read from Primary
    #     assert_equal 0, User.where(:name => @name, :address => @address).count

    #     # Write to primary
    #     assert_equal true, @user.save!

    #     # Read from Non-replicated replica
    #     assert_equal 0, User.where(:name => @name, :address => @address).count
    #   end

    #   # Read from Non-replicated replica
    #   assert_equal 0, User.where(:name => @name, :address => @address).count
    # end

    # it 'saves to primary, force a read from primary even when _not_ in a transaction' do
    #   # Read from replica
    #   assert_equal 0, User.where(:name => @name, :address => @address).count

    #   # Write to primary
    #   assert_equal true, @user.save!

    #   # Read from replica
    #   assert_equal 0, User.where(:name => @name, :address => @address).count

    #   # Read from Primary
    #   ActiveRecordReplica.read_from_primary do
    #     assert_equal 1, User.where(:name => @name, :address => @address).count
    #   end
    # end

    context 'slave is responsive' do
      let(:user) { User.new(:name => @name, :address => @address) }

      it 'reads from primary' do
        expect(user.save!).to be_truthy
        expect(User.where(:name => @name, :address => @address).count).to eq(1)      
      end
    end

    context 'slave is unresponsive' do
      let(:user) { User.new(:name => @name, :address => @address) }

      it 'reads from primary' do
        expect(user.save!).to be_truthy
        allow(ActiveRecordReplica::Replica).to receive(:connection).and_raise(StandardError)
        expect(User.where(:name => @name, :address => @address).count).to eq(1)      
      end
    end

    context 'slave enabled post application boot' do
      let(:user) { User.new(:name    => @name, :address => @address) }
      
      before do
        ActiveRecord::Base.configurations = YAML::load(ERB.new(IO.read('test/database_replica.yml')).result)
      end

      it 'reads from slave' do
        expect(user.save!).to be_truthy
        expect(User.where(:name => @name, :address => @address).count).to eq(0)
        ActiveRecord::Base.configurations = YAML::load(ERB.new(IO.read('test/database.yml')).result)
        expect(user.save!).to be_truthy
        expect(User.where(:name => @name, :address => @address).count).to eq(1)
      end
    end

    after do
      ActiveRecord::Base.establish_connection(:test)
      cleanup
      ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations['test']['slave'])
      cleanup
    end

    def cleanup
      User.delete_all
    end
  end
end