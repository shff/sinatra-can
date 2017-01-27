require 'spec_helper'

describe 'sinatra-can 2' do
  include Rack::Test::Methods

  class MyAppAR < Sinatra::Application
  end

  def app
    MyAppAR
  end

  before :all do
    ActiveRecord::Base.connection.execute('CREATE TABLE user2s ("id" INTEGER PRIMARY KEY NOT NULL, "name" varchar(255) NOT NULL)')
    ActiveRecord::Base.connection.execute('CREATE TABLE article2s ("id" INTEGER PRIMARY KEY NOT NULL, title varchar(255) NOT NULL)')

    class Article2 < ActiveRecord::Base
    end

    class User2 < ActiveRecord::Base
      def is_admin?
        name == "admin"
      end
    end

    app.ability do |user|
      can :edit, :all if user.is_admin?
      can :read, :all
      can :read, Article2
      can :list, User2 if user.is_admin?
      can :list, User2, :id => user.id
      cannot :create, Article2
    end

    app.set :dump_errors, true
    app.set :raise_errors, true
    app.set :show_exceptions, false

    User2.create(:name => 'admin')
    User2.create(:name => 'guest')
  end

  it "should allow management to the admin user" do
    app.user { User2.find_by_name('admin') }
    app.get('/1') { can?(:edit, :all).to_s }
    get '/1'
    last_response.body.should == 'true'
  end

  it "shouldn't allow management to the guest" do
    app.user { User2.find_by_id(2) }
    app.get('/2') { cannot?(:edit, :all).to_s }
    get '/2'
    last_response.body.should == 'true'
  end

  it "should act naturally when authorized" do
    app.user { User2.find_by_id(1) }
    app.get('/3') { authorize!(:edit, :all); 'okay' }
    get '/3'
    last_response.body.should == 'okay'
  end

  it "should raise errors when not authorized" do
    app.user { User2.find_by_id(2) }
    app.get('/4') { authorize!(:edit, :all); 'okay' }
    get '/4'
    last_response.status.should == 403
  end

  it "shouldn't allow a rule if it's not declared" do
    app.user { User2.find_by_id(1) }
    app.get('/6') { can?(:destroy, :all).to_s }
    get '/6'
    last_response.body.should == "false"
  end

  it "should throw 403 errors upon failed conditions" do
    app.user { User2.find_by_id(1) }
    app.get('/7', :can => [ :create, User2 ]) { 'ok' }
    get '/7'
    last_response.status.should == 403
  end

  it "should accept conditions" do
    app.user { User2.find_by_id(1) }
    app.get('/8', :can => [ :edit, :all ]) { 'ok' }
    get '/8'
    last_response.status.should == 200
  end

  it "should accept not_auth and redirect when not authorized" do
    app.user { User2.find_by_id(2) }
    app.get('/login') { 'login here' }
    app.get('/9') { authorize! :manage, :all, :not_auth => '/login'  }
    get '/9'
    follow_redirect!
    last_response.body.should == 'login here'
  end

  it "should autoload and autorize the model" do
    article = Article2.create(:title => 'test1')

    app.user { User2.find_by_id(1) }
    app.get('/10/:id') { load_and_authorize!(Article2); @article2.title }
    get '/10/' + article.id.to_s
    last_response.body.should == article.title
  end

  it "should shouldn't allow creation of the model" do
    article = Article2.create(:title => 'test2')

    app.user { User2.find_by_id(1) }
    app.post('/11', :model => ::Article2) { }
    post '/11'
    last_response.status.should == 403
  end

  it "should autoload and autorize the model when using the condition" do
    article = Article2.create(:title => 'test3')

    app.user { User2.find_by_id(1) }
    app.get('/12/:id', :model => ::Article2) { @article2.title }
    get '/12/' + article.id.to_s
    last_response.body.should == article.title
  end

  it "should autoload when using the before do...end block" do
    article = Article2.create(:title => 'test4')

    app.user { User2.find_by_id(1) }
    app.before('/13/:id', :model => Article2) { }
    app.get('/13/:id') { @article2.title }
    get '/13/' + (article.id).to_s
    last_response.body.should == article.title
  end

  it "should return a 404 when the autoload fails" do
    dummy = Article2.create(:title => 'test4')

    app.user { User2.find_by_id(1) }
    app.get('/article14/:id', :model => Article2) { }
    get '/article14/999'
    last_response.status.should == 404
  end

  it "should autoload a collection as the admin" do
    app.user { User2.find_by_id(1) }
    app.get('/15', :model => User2) { @user2.where(:name => 'admin').count.to_s }
    get '/15'
    last_response.body.should == '1'
  end

  it "should only partially load a collection as a guest" do
    app.user { User2.find_by_id(2) }
    app.get('/16', :model => User2) { @user2.where(:name => 'admin').count.to_s }
    get '/16'
    last_response.body.should == "0"
  end
end
