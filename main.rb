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
#FILE_FORMAT = "wav"

def dbg(*args)
  warn "#{DateTime.now.strftime('%H-%M-%S_%L')}: #{args}"
end

def dbg_dump_position(pos)
  if pos.slice
    dbg("Position: #{pos.timecode} / #{pos.slice.file} @ #{pos.slice.offset} + #{pos.offset}")
  else
    dbg("Position: #{pos.timecode} / #{pos.offset}")
  end
end

def dbg_dump_slices(slice)
  while slice.predecessor
    slice = slice.predecessor
  end
  timecode = 0
  while slice
    if slice.duration != nil
      warn "#{DateTime.now.strftime('%H-%M-%S_%L')}: @#{"% 5d" % timecode}: #{slice.file} (#{"% 5d" % slice.duration}) => [#{timecode}...#{timecode + slice.duration})"
      timecode += slice.duration
    else
      warn "#{DateTime.now.strftime('%H-%M-%S_%L')}: @#{"% 5d" % timecode}: #{slice.file} => [#{timecode}...)"
    end
    slice = slice.successor
  end
end

@context = StateMachineContext.new
@state = StateInitial.instance
@keep_running = true

def process(cmd)
  dbg("processing `#{cmd}'")
  case cmd
  when /^\s*(#.*)?$/
    # comment => ignore
  when /^quit$/
    @state = @state.reset(@context)
    @keep_running = false
    return
  #when /^parse (.*)$/
  #  cmds = File.open($1).readlines()
  #  cmds.each {|c| process(c.chomp)}
  when /^open (.*)$/
    init_state = @state.reset(@context)
    @state = init_state.open(@context, $1)
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
    
  when /^speed ((play|stop) )?(abs|rel) (.*)$/
    if $1
      case $2
      when "play"
        @state = @state.play(@context)
      when "stop"
        @state = @state.stop(@context)
      else
        warn "unknown argument to command speed: `#{$2}'"
      end
    end
    case $3
    when "abs"
      mode = :absolute
    when "rel"
      mode = :relative
    else
      raise "programming error"
    end
    value = $4.to_f
    @state = @state.speed(@context, value, mode)
      
  when /^seek (.*)$/
    arg = $1
    
    sign = ""
    amount = nil
    
    case arg
    when /^([+\-])(.*)$/
      mode = :relative
      sign = $1
      amount = $2
    when /^z(.*)$/
      mode = :end_offset
      amount = $1
    else
      mode = :absolute
      amount = arg
    end

    position = nil
    case amount
    when /^\d+$/
      position = (sign + amount).to_i
    #when /^((\d+):)?((\d+):)?(\d+\.?\d*)s?$/
    #  position = "#{sign}1".to_i * ((($1.to_i * 60 + $2.to_i) * 60 + $3.to_f) * 1000).to_i
    #when /^(\d+\.?\d*)%$/
    #  position = XXX
    else
      warn "invalid seek argument"
    end

    @state = @state.seek(@context, position, mode) if position
    
  when /^set_marker( (.*))?$/
    @state = @state.set_marker(@context, $1)
    
  when /^seek_marker ([+\-]?\d+)$/
    @state = @state.seek_marker(@context, $1.to_i)
    
  when /^rm_marker( (.*))?$/
    raise "not yet supported"
    
  else
    warn "unknown command: `#{cmd.chomp}'"
    
  end

  dbg_dump_position(@context.pos)
end

while @keep_running
  cmd = STDIN.gets
  if cmd
    process(cmd.chomp)
  else
    break
  end
end
