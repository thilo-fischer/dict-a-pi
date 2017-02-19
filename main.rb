#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

# Copyright (c) 2016-2017  Thilo Fischer.
#
# This file is part of dictapi.
#
# dictapi is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# dictapi is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with tobak.  If not, see <http://www.gnu.org/licenses/>.

# TODOs
# - markers as sorted set
# - deletion
# - player/recorder thread

require 'singleton'
require 'date'

require_relative 'datstructure.rb'
require_relative 'states.rb'

# path where to store recorded audio files
AUDIO_DIR = "."

# time in milliseconds allowed to round to get to audio slice edges or markers
LATCH_TOLERANCE = 200

# must be file extension recognized by sox
FILE_FORMAT = "mp3"

def dbg(*args)
  warn "#{DateTime.now.strftime('%H-%M-%S_%L')}: #{args}"
end

@context = StateMachineContext.new
@state = StateInitial.instance
@keep_running = true

def process(cmd)
  case cmd
  when /^\s*(#.*)?$/
    # comment => ignore
  when /^quit$/
    @state = @state.reset(@context)
    @keep_running = false
  when /^open (.*)$/
    cmds = File.open($1).readlines()
    cmds.each {|c| process(c)}
  when /^load (.*)$/
    @state = @state.reset(@context)
    @state = @state.load(@context, $1)
  when /^record$/
    @state = @state.record(@context)
  when /delete( (.*))?/
    # TODO: optional arguments
    @state = @state.delete(@context, $1)
  when /^play$/
    @state = @state.play(@context)
  when /^stop$/
    @state = @state.stop(@context)
  when /^pause$/
    @state = @state.pause(@context)
  when /^resume$/
    @state = @state.resume(@context)
  when /^speed (play|stop)? (abs|rel) (.*)$/
    case $1
    when "play"
      @state = @state.play(@context)
    when "stop"
      @state = @state.stop(@context)
    when ""
      nil
    else
      raise "programming error"
    end
    case $2
    when "abs"
      mode = :absolute
    when "rel"
      mode = :relative
    else
      raise "programming error"
    end
    value = $3.to_f
    @state = @state.speed(@context, value, mode)
      
#  when /^seek (.*)$/
#    arg = $1
#    case arg
#    when /^[+\-](.*)$/
#      mode = :relative
#    when /^#(.*)$/
#      mode = :end_offset
#    else
#      mode = :absolute
#    end
#    amount = $1 # XXX
#    case arg
#    when /^(\d+\.?\d*)%$/
#      amount = XXX
#    when /^(\d+\.?\d*)s$/
#      amount = $1.to_iXXX * 1000
#    when /^(\d+):(\d+\.?\d*)s$/
#      amount = ($1.XXX * 60 + $2.to_iXXX) * 1000
#    when /^\d+\.?|\d*\.\d+$/
#      amount = $1.to_iXXX
#    else
#      warn "invalid speed argument"
#    end
#    @state = @state.seek(amount, mode)
    
  when /^set_marker( (.*))?$/
    @state = @state.set_marker(@context, $1)
  when /^seek_marker [+\-]?(\d+)$/
    @state = @state.seek_marker(@context, $1.to_i)
  when /^rm_marker( (.*))?$/
    raise "not yet supported"
  else
    warn "unknown command: `#{cmd.chomp}'"
  end
end

while @keep_running
  cmd = STDIN.gets
  process(cmd)
end
