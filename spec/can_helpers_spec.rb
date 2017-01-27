require 'rspec'
require './lib/sinatra/can'

require 'ostruct'

describe 'Sinatra::Can' do
  before(:each) do
    @helpers = Object.new
    @helpers.extend Sinatra::Can::Helpers
  end

  describe "can?" do 
    it "should forbid stuff that's not declared" do
      @helpers.can?(:delete, :something).should be_false
    end

    it "should support the cannot? query" do
      @helpers.cannot?(:delete, :everything).should be_true
    end

    it "should allow editing everything when the subject is :all" do
      @helpers.can(:edit, :all)
      @helpers.can?(:edit, :user).should be_true
      @helpers.can?(:delete, :user).should be_false
    end

    it "should allow creating and only creating an article" do
      @helpers.can(:create, :article)
      @helpers.can?(:create, :article).should be_true
      @helpers.can?(:delete, :article).should be_false
    end

    it "should allow anything when :manage is declared" do
      @helpers.can(:manage, :user)
      @helpers.can?(:delete, :user).should be_true
    end

    it "should allow exceptions via cannot" do
      @helpers.can(:manage, :user)
      @helpers.cannot(:kick, :user)
      @helpers.can?(:kick, :user).should be_false
    end

    it "should respect block conditions" do
      @helpers.can(:read, String) { |value| value == "yes" }
      @helpers.can?(:read, "yes").should be_true
      @helpers.can?(:read, "no").should be_false
    end

    it "should accept non-nil/false values as true on blocks" do
      @helpers.can(:read, String) { "sure" }
      @helpers.can?(:read, "test").should be_true
    end

    it "should try every block" do
      @helpers.can(:read, Integer) { |i| i == 1 }
      @helpers.can(:read, Integer) { |i| i == 2 }
      @helpers.can?(:read, 1).should be_true
      @helpers.can?(:read, 2).should be_true
      @helpers.can?(:read, 3).should be_false
    end

    it "should allow multiple actions in a single declaration" do
      @helpers.can([:read, :write], :file)
      @helpers.can?(:read, :file).should be_true
      @helpers.can?(:write, :file).should be_true
      @helpers.can?(:delete, :file).should be_false
    end

    it "should allow multiple subjects in a single declaration" do
      @helpers.can(:view, [String, Symbol])
      @helpers.can?(:view, "hi").should be_true
      @helpers.can?(:view, :hi).should be_true
      @helpers.can?(:view, 10).should be_false
    end

    it "should allow ancestors" do
      @helpers.can(:list, Numeric)
      @helpers.can?(:list, Integer).should be_true
      @helpers.can?(:list, 1.2).should be_true
      @helpers.can?(:list, "this").should be_false
    end

    it "should pass additional parameters to blocks" do
      @helpers.can(:read, Integer) do |a,b|
        a.should == 10
        b.should == 20
        @block_called = true
      end
      @helpers.can?(:read, 10, 20)
      @block_called.should be_true
    end

    it "should allow conditions" do
      @helpers.can(:number, Integer, :to_i => 1)
      @helpers.can?(:number, 1).should be_true
      @helpers.can?(:number, 2).should be_false
    end

    it "should allow arrays in conditions" do
      @helpers.can(:read, Integer, :to_i => [1,2,3])
      @helpers.can?(:read, 2).should be_true
      @helpers.can?(:read, 10).should be_false
    end

    it "should allow ranges in conditions" do
      @helpers.can(:read, Integer, :to_i => 1..5)
      @helpers.can?(:read, 2).should be_true
      @helpers.can?(:read, 10).should be_false
    end

    it "should match at least one element of an array with a single value in the condition" do
      @helpers.can(:read, Array, :to_a => { :to_i => 2 })
      @helpers.can?(:read, [1,2,3]).should be_true
      @helpers.can?(:read, [3,4,5]).should be_false
    end

    it "should allow nested hashes in conditions" do
      @helpers.can(:read, Integer, :to_i => { :to_i => 2 })
      @helpers.can?(:read, 2).should be_true
      @helpers.can?(:read, 3).should be_false
    end

    it "should not stop at cannot when using conditions" do
      @helpers.can(:read, Integer)
      @helpers.cannot(:read, Integer, :to_i => 2)
      @helpers.can?(:read, 1).should be_true
      @helpers.can?(:read, 2).should be_false
      @helpers.can?(:read, 3).should be_true
    end

    it "should match nested objects" do
      @helpers.can(:read, Array, :first => { :to_i => 1 })
      @helpers.can?(:read, [1,2,3]).should be_true
      @helpers.can?(:read, [3,2,1]).should be_false
    end

    it "should accept included modules as being inherited" do
      module A; end
      class B; include A; end
      class C; end
      @helpers.can(:read, A)
      @helpers.can?(:read, B).should be_true
      @helpers.can?(:read, C).should be_false
    end

    it "should accept multiple classes and inheritance" do
      @helpers.can(:read, [ Numeric, Enumerable])
      @helpers.can?(:read, 1).should be_true
      @helpers.can?(:read, []).should be_true
      @helpers.can?(:read, {}).should be_true
      @helpers.can?(:read, "hi").should be_false
    end
  end

  describe "authorize" do
    it "should authorize when allowed" do
      @helpers.can(:read, :data)
      @helpers.authorize!(:read, :data, :not_auth => 'hi').should == nil
    end

    it "should redirect when not allowed" do
      @helpers.stub(:redirect) { 'redirecting' }
      @helpers.authorize!(:read, :data, :not_auth => 'hi').should == 'redirecting'
    end
  end

  describe "load_and_authorize!" do
    before :each do
      class Settings; def not_auth; 1; end; end
      class User < OpenStruct; def self.find(id); User.new; end; end
      class RedirectError < Exception; end

      @helpers.stub(:settings) { Settings.new }
      @helpers.stub(:redirect) { raise RedirectError.new }
    end

    it "should GET a resource" do
      @helpers.stub(:env) {{"REQUEST_METHOD" => 'GET'}}
      @helpers.stub(:params) {{:id => '1' }}

      @helpers.can(:read, User)
      @helpers.load_and_authorize!(User)
      @helpers.instance_variable_get('@user').should be_a User
    end

    it "should POST a resource with preloaded conditions" do
      @helpers.stub(:env) {{"REQUEST_METHOD" => 'POST'}}
      @helpers.stub(:params) {{}}

      @helpers.can(:create, User, :field => 'ok')
      @helpers.load_and_authorize!(User)
      @helpers.instance_variable_get('@user').field.should == 'ok'
    end

    it "should not POST a resource when unauthorized" do
      @helpers.stub(:env) {{"REQUEST_METHOD" => 'POST'}}
      @helpers.stub(:params) {{}}

      lambda { @helpers.load_and_authorize!(User) }.should raise_error RedirectError
    end

    it "should POST a resource with form parameters" do
      @helpers.stub(:env) {{"REQUEST_METHOD" => 'POST'}}
      @helpers.stub(:params) {{ :user => { :field => 'ok' }}}

      @helpers.can(:create, User)
      @helpers.load_and_authorize!(User)
      @helpers.instance_variable_get('@user').field.should == 'ok'
    end

    it "should POST a resource with preloaded conditions AND form parameters" do
      @helpers.stub(:env) {{"REQUEST_METHOD" => 'POST'}}
      @helpers.stub(:params) {{ :id => '1', :user => { :field => 'ok', :field2 => 'ok2' }}}

      @helpers.can(:create, User, :field => 'ok')
      @helpers.load_and_authorize!(User)
      @helpers.instance_variable_get('@user').field.should == 'ok'
      @helpers.instance_variable_get('@user').field2.should == 'ok2'
    end

    it "should not POST a resource when conditions don't match form parameters" do
      @helpers.stub(:env) {{"REQUEST_METHOD" => 'POST'}}
      @helpers.stub(:params) {{ :id => '1', :user => { :field => 'ok', :field2 => 'ok2' }}}

      @helpers.can(:update, User, :field => 'not ok')
      
      lambda { @helpers.load_and_authorize!(User) }.should raise_error RedirectError
    end

    it "should PUT a resource with form parameters" do
      @helpers.stub(:env) {{"REQUEST_METHOD" => 'PUT'}}
      @helpers.stub(:params) {{ :id => '1', :user => { :field => 'ok', :field2 => 'ok2' }}}

      @helpers.can(:update, User)
      @helpers.load_and_authorize!(User)
      @helpers.instance_variable_get('@user').field.should == 'ok'
      @helpers.instance_variable_get('@user').field2.should == 'ok2'
    end

    it "should not PUT a resource when conditions don't match form parameters" do
      @helpers.stub(:env) {{"REQUEST_METHOD" => 'PUT'}}
      @helpers.stub(:params) {{ :id => '1', :user => { :field => 'ok' }}}

      @helpers.can(:update, User, :field => 'not ok')
      lambda { @helpers.load_and_authorize!(User) }.should raise_error RedirectError
    end

    it "should GET a collection" do
      @helpers.stub(:env) {{"REQUEST_METHOD" => 'GET'}}
      @helpers.stub(:params) {{}}

      @helpers.can(:list, User)
      @helpers.load_and_authorize!(User)
      #@helpers.instance_variable_get("@user").should be_kind_of Array
    end

    it "should PUT certain form parameters" do
      @helpers.stub(:env) {{"REQUEST_METHOD" => 'PUT'}}
      @helpers.stub(:params) {{ :id => 1, :user => { :field => 'ok' }}}

      #@helpers.can(:update, User, [:field])
      #@helpers.load_and_authorize!(User)
      #@helpers.instance_variable_get("@user").field.should == 'ok'
    end

    it "should not PUT unauthorized form parameters" do
      @helpers.stub(:env) {{"REQUEST_METHOD" => 'PUT'}}
      @helpers.stub(:params) {{ :id => 1, :user => { :field => 'ok', :field2 => 'not ok' }}}

      @helpers.can(:update, User, [:field])
      #lambda { @helpers.load_and_authorize!(User) }.should raise_error RedirectError
    end
  end
end
