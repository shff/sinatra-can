require 'spec_helper'

describe 'sinatra-can' do
  include Rack::Test::Methods

  class MyAppDM < Sinatra::Application
  end

  def app
    MyAppDM
  end

  before :all do
    DataMapper.setup(:default, 'sqlite::memory:')

    class Articledm
      include DataMapper::Resource

      property :id, Serial
      property :title, String
    end

    class Userdm
      include DataMapper::Resource

      property :id, Serial
      property :name, String

      def is_admin?
        @name == "admin"
      end
    end

    DataMapper.finalize
    DataMapper.auto_migrate!

    app.ability do |user|
      can :edit, :all if user.is_admin?
      can :read, :all
      can :read, Articledm
      cannot :create, Articledm
      can :list, Userdm if user.is_admin?
      can :list, Userdm, :id => user.id
    end

    app.set :dump_errors, true
    app.set :raise_errors, true
    app.set :show_exceptions, false

    Userdm.create(:name => 'admin')
    Userdm.create(:name => 'guest')
  end

  it "should allow management to the admin user" do
    app.user { Userdm.get(1) }
    app.get('/1') { can?(:edit, :all).to_s }
    get '/1'
    last_response.body.should == 'true'
  end

  it "shouldn't allow management to the guest" do
    app.user { Userdm.get(2) }
    app.get('/2') { cannot?(:edit, :all).to_s }
    get '/2'
    last_response.body.should == 'true'
  end

  it "should act naturally when authorized" do
    app.user { Userdm.get(1) }
    app.get('/3') { authorize!(:edit, :all); 'okay' }
    get '/3'
    last_response.body.should == 'okay'
  end

  it "should raise errors when not authorized" do
    app.user { Userdm.get(2) }
    app.get('/4') { authorize!(:edit, :all); 'okay' }
    get '/4'
    last_response.status.should == 403
  end

  it "shouldn't allow a rule if it's not declared" do
    app.user { Userdm.get(1) }
    app.get('/6') { can?(:destroy, :all).to_s }
    get '/6'
    last_response.body.should == "false"
  end

  it "should throw 403 errors upon failed conditions" do
    app.user { Userdm.get(1) }
    app.get('/7', :can => [ :create, Userdm ]) { 'ok' }
    get '/7'
    last_response.status.should == 403
  end

  it "should accept conditions" do
    app.user { Userdm.get(1) }
    app.get('/8', :can => [ :edit, :all ]) { 'ok' }
    get '/8'
    last_response.status.should == 200
  end

  it "should accept not_auth and redirect when not authorized" do
    app.user { Userdm.get(2) }
    app.get('/login') { 'login here' }
    app.get('/9') { authorize! :manage, :all, :not_auth => '/login'  }
    get '/9'
    follow_redirect!
    last_response.body.should == 'login here'
  end

  it "should autoload and autorize the model" do
    article = Articledm.create(:title => 'test1')

    app.user { Userdm.get(1) }
    app.get('/10/:id') { load_and_authorize!(Articledm); @articledm.title }
    get '/10/' + article.id.to_s
    last_response.body.should == article.title
  end

  it "should shouldn't allow creation of the model" do
    article = Articledm.create(:title => 'test2')

    app.user { Userdm.get(1) }
    app.post('/11', :model => [ Articledm ]) { }
    post '/11'
    last_response.status.should == 403
  end

  it "should autoload and autorize the model when using the condition" do
    article = Articledm.create(:title => 'test3')

    app.user { Userdm.get(1) }
    app.get('/12/:id', :model => [ Articledm ]) { @articledm.title }
    get '/12/' + article.id.to_s
    last_response.body.should == article.title
  end

  it "should autoload when using the before do...end block" do
    article = Articledm.create(:title => 'test4')

    app.user { Userdm.get(1) }
    app.before('/13/:id', :model => [ Articledm ]) { }
    app.get('/13/:id') { @articledm.title }
    get '/13/' + (article.id).to_s
    last_response.body.should == article.title
  end

  it "should return a 404 when the autoload fails" do
    dummy = Articledm.create(:title => 'test4')

    app.user { Userdm.get(1) }
    app.get('/article14/:id', :model => [ Articledm ]) { @articledm.title }
    get '/article14/999'
    last_response.status.should == 404
  end

  it "should autoload a collection as the admin" do
    app.user { Userdm.get(1) }
    app.get('/15d', :model => [ Userdm ]) { @userdm.all(:name => 'admin').count.to_s }
    get '/15d'
    last_response.body.should == '1'
  end

  it "should 403 on autoloading a collection when being a guest" do
    app.user { Userdm.get(2) }
    app.get('/16d', { :model => [ Userdm ] }) { @userdm.all(:name => 'admin').count.to_s }
    get '/16d'
    last_response.body.should == "0"
  end
end
