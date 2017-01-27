require 'rspec'
require 'rack/test'
require 'sinatra'
require 'dm-core'
require 'dm-migrations'
require 'active_record'
require './lib/sinatra/can'

ActiveRecord::Base.establish_connection(:adapter => 'sqlite3', :database => ':memory:')
