Sinatra::Can
============

Sinatra::Can is a lightweight Sinatra port of the CanCan authorization library. It contains a partial implementation of CanCan's Rails helpers, but in Sinatra.

Check out CanCan if you don't know it: https://github.com/ryanb/cancan/

## Installing

To install this gem, just use the gem command:

    gem install sinatra-can

To use it in your project, just require it:

    require 'sinatra/can'

## Abilities

Abilities are defined using the `can` and `cannot` methods. You have to declare those abilities before using the calling methods. The recommended way is using Sinatra's `before` callback.

Here's the canonical example, which gives permission for admin users to manage and for non-admins to read:

    before do
      user = User.find_by_id(session[:user_id])

      can :manage, :all if user.admin?
      can :read, :all
    end

You can use blocks too, just like CanCan:

    before do
      user = User.find_by_id(session[:user_id])

      if user.is_admin?
        can :kick, User do |victim|
          !victim.is_admin?
        end
      end
    end

The possibility to use a Rails' CanCan class was dropped from this gem.

## Checking Abilities

The can? method receives an action and an object as parameters and checks if the current user is allowed, as declared in the Ability. This method is a helper that can be used inside blocks:

    can? :destroy, @project
    cannot? :edit, @project

If you haven't instantiated the objects, you can check classes as well:

    can? :create, Project

And in views too:

    <% if can? :create, Project %>
      <%= link_to "New Project", new_project_path %>
    <% end %>

## Authorizing

Authorization in CanCan is extremely easy. You just need a single line inside your routes:

    def '/admin' do
      authorize! :admin, :all

      haml :admin
    end

If the user isn't authorized, your app will return a RESTful 403 error, but you can also instruct it to redirect to other pages by defining this setting at your Sinatra configuration.

    set :not_auth, '/login'

Or directly in the authorize! command itself:

    authorize! :admin, :all, :not_auth => '/login'

Sinatra lacks controllers, but you can use "before" blocks to restrict groups of routes with wildcards (or even regular expressions). In this case you'll only be able to access the pages under /customers/ if your user is authorized to ":manage" some "Customers".

    before '/customers/*' do
      authorize! :manage, Customers
    end

## Resource Conditions

You can authorize based on model attributes as well. You can pass a hash of conditions as the last attribute on `can` or `cannot`. Here's an example: maybe you just want an user to see Projects owned by his own group.

    before do
      user = User.find_by_id(session[:user_id])

      can :access, Projects, :group_id => user.group_id
    end

This condition works with all the other helpers, and provide you with even more granularity and ease of ability declaration.

## Sinatra 'Can' Condition

There is a built-in condition called :can that can be used in your blocks. It returns 403 when the user has no access. It basically replaces the authorize! method.

    get '/admin', :can => [ :admin, :all ] do
      haml :admin
    end

## Load and Authorize

load_and_authorize is one of CanCan's greatest features. It will, if applicable, load a model based on the :id parameter, and authorize, according to the HTTP Request Method.

The usage with this Sinatra adapter is a bit different and way simpler. Since Sinatra is based on routes (as opposed to controllers + methods), you need to tell which model you want to use. It will guess the action (:view, :create, etc) using the HTTP verb, and an 'id' parameter to load the model.

It is compatible with ActiveRecord, DataMapper and Sequel.

Here's the syntax:

    get '/projects/:id' do
      load_and_authorize! Project

      # It's loaded now.
      @project.name
    end

There's also a handy condition:

    get '/projects/:id', :model => Project do
      @project.name
    end

You can load collections too, with both syntaxes. Just use a `get` handler, without an `:id` property:

    get '/projects', :model => Project do
      # here are your projects
      @project
    end

Both collection loading and individual entity loading will respect the resource conditions.

Authorization happens right after autoloading, and depends on the HTTP verb. Here's the CanCan actions for each verb:

 - :list (get without an :id)
 - :view (get)
 - :create (post)
 - :update (put or patch)
 - :delete (delete)

So, for a model called Projects, you can define your abilities like this, for example:

    before do
      user = User.find_by_id(params[:user_id])

      can :list, Project
      can :view, Project
      can :create, Project if user.is_manager?
      can :update, Project if user.is_admin?
      can :delete, Project if user.is_admin?
    end

## Alert:

DataMapper Models are problematic when used with Sinatra conditions, since DataMapper turns the class constant into a method, and Sinatra evaluates every parameter. So, when using it with the :model condition, wrap it with brackets:

    get '/users', :model => [ Users ] do
      # etc
    end

## Modular Style

To use this gem in Modular Style apps, you just need to register it:

    class MyApp < Sinatra::Base
      register Sinatra::Can

      ...
    end

## Example App

Here's here's an example app using Modualar-style.

To test, pass your user name via the ?user= query string. `/secret?user=admin` should be accessible, but `/secret?user=someone_else` should be off limits.

    require 'rubygems'
    require 'sinatra'
    require 'sinatra/can'

    class MyApp < Sinatra::Base
      register Sinatra::Can

      before do
        user = params[:user]

        can :read, :secret if user == "admin"
      end

      error 403 do
        'not authorized'
      end

      get '/secret' do
        authorize! :read, :secret
        'you can read it'
      end
    end

    use MyApp