#!/usr/bin/env ruby
# -*- encoding : utf-8 -*-

require 'rubygems'
require 'fsdb'
require 'yaml'

### Domain model
#
class Dice
  attr_reader :name, :faces

  def initialize name, faces
    @name, @faces = name, faces
    @throws = Array.new faces, 0
  end

  def valid?(value)  value.to_i.between? 1, @faces  end

  def throws()  @throws.reduce(0, :+)  end

  def average
    sum = 0
    @throws.each_with_index do |occurrences,face_i|
      sum += (face_i + 1) * occurrences
    end
    sum.to_f / self.throws
  end

  def throw value
    return unless valid?(value)
    face_index = value.to_i - 1
    @throws[face_index] += 1
  end


  class Database

    def initialize database_path
      @db = FSDB::Database.new database_path,
        formats: [FSDB::Formats::YAML_FORMAT] + FSDB::Database::FORMATS
    end

    def dice_file(name) "dice/#{name}.yaml" end

    def all
      result = []
      @db.browse_each_child 'dice/' do |_,d| result << d end
      result.sort_by! { |d| d.name }
    rescue FSDB::Database::MissingObjectError
      []
    end

    def add dice
      @db.replace(dice_file(dice.name)) do |d|
        raise AlreadyExists unless d.nil?
        dice
      end
    end

    def find(name, &block)  @db.browse(dice_file(name), &block)  end

    def edit(name, &block)  @db.edit(dice_file(name), &block)  end

    class AlreadyExists < StandardError; end
  end
end


### Command-line user interface
#
require 'commander/import'

def abort_usage msg
  abort "#{msg}\n\nUsage: #{Commander::Runner.instance.active_command.syntax}"
end

OPTIONS_DEFAULTS = {
  faces: 6,
  data: '~/.dice'
}


program :name, 'dice'
program :version, '0.0.1'
program :description, 'Record statistics for my dice'

global_option '--data DIR', 'Location of the dice & statistics data.'


command :list do |c|
  c.syntax = 'dice list'
  c.summary = 'List known dice.'
  c.action do |args, options|
    options.default OPTIONS_DEFAULTS
    db = Dice::Database.new options.data
    db.all.each do |d|
      throws = d.throws
      stats = if throws.zero?
                "-- (no stats yet)"
              else
                "averaging %0.1f over %d throws" % [d.average, throws]
              end
      puts "#{d.name}\t#{stats}"
    end
  end
end
default_command :list


command :new do |c|
  c.syntax = 'dice new [-f <faces>] <name> ...'
  c.summary = 'Make a new dice to record data for.'
  c.option '-f', '--faces NUMBER', Integer, 'Specify number of faces (default 6)'
  c.action do |args, options|
    options.default OPTIONS_DEFAULTS
    abort_usage "You must specify at least one <name>." if args.empty?

    db = Dice::Database.new options.data
    args.each do |name|
      new_dice = Dice.new name, options.faces
      begin
        db.add new_dice
      rescue Dice::Database::AlreadyExists
        say_warning "A dice named #{name} already exists, pick a different name."
      end
    end
  end
end


command :throw do |c|
  c.syntax = 'dice throw <name> <value> …'
  c.summary = 'Record thrown values for each of the given dice.'
  c.action do |args, options|
    options.default OPTIONS_DEFAULTS
    abort_usage "You must pass one <value> for each <name>." unless args.size.even?

    db = Dice::Database.new options.data

    # validate everything beforehand
    args.each_slice(2) do |name,value|
      db.find name do |d|
        abort "Unknown dice #{name}." if d.nil?
        abort "Invalid value #{value} for dice #{name}" unless /^\d+$/ === value and d.valid?(value)
      end
    end

    args.each_slice(2) do |name,value|
      db.edit(name) do |d|
        d.throw value
      end
    end
  end
end


command :run do |c|
  c.syntax = 'dice run <name> …'
  c.summary = 'Record a series of throws of one or more dice.'
  c.action do |args, options|
    options.default OPTIONS_DEFAULTS
    abort_usage "You must pass at least one <name>." if args.empty?

    db = Dice::Database.new options.data

    args.each do |name|
      db.find name do |d|
        abort "Unknown dice #{name}" if d.nil?
      end
    end

    begin
      conversion = lambda { |str| str.split.collect{ |e| e.to_i }}
      i = 1
      loop do
        values = ask("#{args.join(' ')} ?  (throw ##{i})", conversion)
        if values.size == args.size
          args.zip values do |name,value|
            db.edit name do |d| d.throw value end
          end
          i += 1
        else
          say_warning "Wrong number of values!"
        end
      end
    rescue EOFError
    end
  end
end


command :stats do |c|
  c.syntax = 'dice stats [options]'
  c.summary = ''
  c.action do |args, options|
    # Do something or c.when_called Dice::Commands::Stats
  end
end

