module Sinatra
  # Sinatra::Can is a lightweight version of the CanCan authorization library.
  # It contains a partial implementation of CanCan's Rails helpers, but in
  # Sinatra.
  #
  # Since the development of CanCan stopped around 2011-2012, this gem
  # implemented its features from scratch, without dependencies other than
  # Sinatra itself.
  #
  # Check out CanCan if you don't know it: https://github.com/ryanb/cancan/
  #
  module Can
    # Helpers for Sinatra
    module Helpers
      # The `can` method defines a new ability that can be done in the current
      # context.
      #
      # They can be placed anywhere, but they must be set before the checking
      # methods are used. The `before do` block is recommended:
      #
      #   before do
      #     can :view, User
      #     can :create, User
      #     can :create, Post
      #
      # You can use Ruby syntax normally:
      #
      #     can :delete, User if current_user.is_admin?
      #     cannot :create, Post if current_user.is_banned?
      #
      # Having abilities being checked against user permissions is the most
      # common use-case.
      #
      # You can also use blocks to lazy-check resources:
      #
      #     can :delete, Article do |article|
      #       # only delete if it was created less than an hour ago
      #       (Time.now - article.created_at) < 3600
      #     end
      #
      # And finally, you can use resource conditions:
      #
      #     can :delete, Post, :owner_id => current_user.user.id
      #   end
      #
      def can(action, subject, conditions = {}, &block)
        rules << Rule.new(true, false, [action].flatten, [subject].flatten,
          conditions, block)
      end

      # The `cannot` method is the opposite of `can`, and is used the same way.
      # It explicitly defines that something cannot be done.
      #
      #   cannot :edit, Post
      #
      def cannot(action, subject, conditions = {}, &block)
        rules << Rule.new(false, true, [action].flatten, [subject].flatten,
          conditions, block)
      end

      # The can? method checks if an ability is allowed now, as declared with
      # the `can` and `cannot` methods, as above. It receives an action and an
      # object (or class) as parameters. This method is a helper that can be
      # used pretty much anywere.
      #
      # For instance:
      #
      #   can? :destroy, @project
      #
      # The code above returns true if the user can access the Project class,
      # and if the specific @project instance is accessible (in case you
      # use conditions or lazy-checking in the Project ability).
      #
      # If you haven't instantiated the object yet, you can check if a classes
      # is accessible:
      # 
      #   can? :create, Project
      #
      # This checks if the user can access the Projects class.
      #
      # You can use it in views too:
      #
      #   <% if can? :create, Project %>
      #     <%= link_to "New Project", new_project_path %>
      #   <% end %>
      #
      def can?(action, subject, *args)
        match = rules_for(action, subject).detect do |rule|
          next rule.block.call(subject, *args)    if rule.block && !(subject.class <= Module)
          next match?(subject, rule.conditions)   if !rule.conditions.empty? && !(subject.class <= Module)
          rule.conditions.empty? || rule.can
        end
        !!match && match.can
      end

      # The `cannot?` methods works just like `can?`, but it's the opposite.
      #
      #   cannot? :edit, @project
      #
      # It works in views and controllers.
      #
      def cannot?(action, subject, *extra_args)
        !can?(action, subject, extra_args)
      end

      # Authorization in CanCan is extremely easy. You just need a single line
      # inside your helpers:
      #
      #   get '/admin' do
      #     authorize! :admin, :all
      #     haml :admin
      #   end
      #
      # If the user isn't authorized, your app will return a RESTful 403 error,
      # but you can also instruct it to redirect to other pages by defining
      # the `not_auth` setting at Sinatra's configuration.
      #
      #   set :not_auth, '/login'
      # 
      # Or directly in the authorize! command itself:
      #
      #   authorize! :admin, :all, :not_auth => '/login'
      #
      # A common use case for authorize! is checking against resources:
      #
      #   authorize! :delete, @project
      #
      def authorize!(action, subject, options = {})
        if cannot?(action, subject, options)
          redirect options[:not_auth] || settings.not_auth || error(403)
        end
      end

      # load_and_authorize is CanCan's neatest feature. It will, if applicable,
      # load a model based on the :id parameter, and authorize, according to
      # the HTTP Request Method.
      # 
      # The usage in Sinatra is a bit different, since it's implemented from
      # scratch for simplicity. It is compatible with ActiveRecord, DataMapper
      # and Sequel.
      #
      #     get '/projects/:id' do
      #       load_and_authorize! Project
      #       @project.name
      #     end
      #
      # In the example above, it will load the project with the id specified
      # in the route fragment.
      #
      # It is also implemented as a handy condition, for expressability. It is
      # just a shortcut. Under the covers, it just calls `load_and_authorize!`
      # for you.
      #
      #     get '/projects/:id', :model => Project do
      #       @project.name
      #     end
      # 
      # You can load collections too, with both syntaxes. Just use a `get`
      # handler, without an `:id` property:
      # 
      #     get '/projects' do
      #       load_and_authorize! Project
      #       # here are your projects, already loaded
      #       @project
      #     end
      # 
      # Both collection loading and individual entity loading will respect the
      # resource conditions. For instance, if you set an ability like this:
      #
      #   can :list, Project, :owner_id => current_user.id
      #
      # ...it will only load projects where the `owner_id` field is the same as
      # the `current_user.id`.
      #
      # Extra authorization happens automatically, and it depends on the HTTP
      # verb used to call the route (you know, `get`, `post`, etc). Here's the
      # CanCan actions that are checked for each verb:
      # 
      # - :list (get without an :id)
      # - :view (get)
      # - :create (post)
      # - :update (put or patch)
      # - :delete (delete)
      #
      def load_and_authorize!(model, options = {})
        model = model.class unless model.is_a? Class
        instance_name = model.name.gsub(/([a-z\d])([A-Z])/,'\1_\2').downcase.split("::").last
        cans = conditions_for(current_operation, model)
        cannots = conditions_for(current_operation, model, :cannot)

        if params[:id]
          instance = model.get(params[:id])    if model.respond_to? :get
          instance = model.find(params[:id])   if model.respond_to? :find and !model.respond_to? :get
          error 404 unless instance
        elsif current_operation == :list
          collection = model.all(cans) - model.all(cannots)     if model.respond_to? :all
          collection = {}                                       if model.respond_to? :where
        elsif current_operation == :create
          instance = model.new(cans)
        end

        parameters = params[instance_name.to_sym]
        parameters.each { |k,v| instance.send("#{k}=", v) } if parameters and instance

        authorize! current_operation, instance || model, options
        self.instance_variable_set("@#{instance_name}", instance || collection)
      rescue
        error 404
      end

      protected

      def current_operation
        case env["REQUEST_METHOD"].upcase
          when 'GET' then params[:id] ? :read : :list
          when 'POST' then :create
          when 'PUT' then :update
          when 'PATCH' then :update
          when 'DELETE' then :destroy
        end
      end

      def conditions_for(action, subject, behavior = :can)
        rules_for(action, subject).select(&behavior).map(&:conditions)
          .inject(&:merge) || {}
      end

      def rules_for(action, subject)
        rules.reverse.select do |rule|
          ((rule.actions.include?(:manage) || rule.actions.include?(action)) &&
            (rule.subjects.include?(:all) || rule.subjects.include?(subject) ||
              rule.subjects.any? { |sub|
                subject <= sub rescue subject.class <= sub
                
              }))
        end
      end

      def match?(subject, conditions)
        conditions.all? do |name, value|
          attribute = subject.send(name)
          if value.kind_of?(Hash)
            if attribute.kind_of? Array
              attribute.any? { |element| match? element, value }
            else
              !attribute.nil? && match?(attribute, value)
            end
          elsif value.kind_of?(Array) || value.kind_of?(Range)
            value.include? attribute
          else
            attribute == value
          end
        end
      end

      def rules
        @rules ||= []
      end
    end

    def self.registered(app)
      app.set(:model) { |subject| condition { load_and_authorize!(subject) } }
      app.set(:not_auth, nil)
      app.helpers Helpers
    end

    Rule = Struct.new(:can, :cannot, :actions, :subjects, :conditions, :block)
  end

  register Can if respond_to? :register
end
