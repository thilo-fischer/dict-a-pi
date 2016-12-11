#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

# Copyright (c) 2016  Thilo Fischer.
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

# time in milliseconds allowed to round to get to audio slice edges or markers
LATCH_TOLERANCE = 200

# Audio slice
class ASlice
  # file - filename of the audio file
  # offset - slice start as milliseconds after start of audio file
  # duration - duration of slice in milliseconds
  # markers - array of objects of class Marker
  attr_accessor :file, :offset, :duration, :markers
  # predecessor, successor - preceeding and succeeding audio slices (doubly linked list)
  attr_accessor :predecessor, :successor
  def initialize(file, offset = 0.0, duration = nil)
    @file = file
    @offset = offset
    @duration = duration
    @markers = []
    @predecessor = nil
    @successor = nil
  end # def initialize
  def insert(offset, slice)
    case offset
    when 0..LATCH_TOLERANCE
      @predecessor.successor = slice if @predecessor
      slice.predecessor = @predecessor
      slice.successor = self
      @predecessor = slice
    when LATCH_TOLERANCE..(duration-LATCH_TOLERANCE)
      split(offset)
      insert(offset, slice)
    when (duration-LATCH_TOLERANCE)..duration
      @successor.predecessor = slice if @successor
      slice.successor = @successor
      slice.predecessor = self
      @successor = slice
    else
      warn "invalid offset: #{offset}"
    end
  end # def insert
  # remove region from offset from (inclusive)
  # till offset to (exclusive) from recording
  def delete(from, to)
    if from < LATCH_TOLERANCE
      # delete from slice beginning till +to+
      if offset > @duration - LATCH_TOLERANCE
        # delete complete slice
        @predecessor.successor = @successor
        @successor.predecessor = @predecessor
      else
        @offset = to
      end
    elsif offset > @duration - LATCH_TOLERANCE
      # delete from +from+ till slice ending
      @duration += from
    else
      # delete from +from+ till +to+
      split(to)
      split(from)
      @successor = @successor.successor
      @successor.predecessor = self
    end
  end
  def split(offset)
    if offset < LATCH_TOLERANCE or offset > @duration - LATCH_TOLERANCE
      warn "invalid offset: #{offset}"
      return
    end
    tail = ASlice.new(@file, @offset + offset, @duration - offset)
    @duration = offset
    @successor.predecessor = tail if @successor
    tail.successor = @successor
    tail.predecessor = self
    @successor = tail
    m_parts = @markers.partition {|m| m.offset < offset}
    @markers = m_parts[0]
    tail.markers = m_parts[1].collect {|m| Marker.new(m.offset - offset) }
  end
  def set_marker(ctx, offset)
    offset = ctx.pos.offset
    case offset
    when 0..LATCH_TOLERANCE
      offset = 0
    when LATCH_TOLERANCE..(ctx.pos.slice.duration-LATCH_TOLERANCE)
      @successor.markers << Marker.new(0)
      return
    end
    m = Marker.new(offset)
    @markers << m
  end
  def update_duration
    `soxi "#{file}.mp3"`.find {|l| l =~ /^Duration\s*:\s*(\d+):(\d\d):(\d\d).(\d+)/}
    ctx.pos.slice.duration = (($1.to_i * 60 + $2.to_i) * 60 + $3.to_i) * 1000 + ($4 + "000")[0..2].to_i
  end
end # class ASlice

class Marker
  # offset - position of marker in milliseconds after start of audio slice
  attr_accessor :offset
  def initialize(offset)
    @offset = offset
  end
end # class Marker

class Position
  attr_accessor :timecode, :slice, :offset
  def initialize
    @timecode = 0
    @slice = nil
    @offset = nil
  end
  # timecode of beginning of current slice
  def slice_begin
    @timecode - @offset
  end
  # timecode of ending of current slice
  def slice_end
    slice_begin + @slice.duration
  end
  def go_slice_begin
    @offset = 0
    @timecode -= @offset
  end
  def go_slice_end
    go_slice_begin
    @offset = @slice.duration
    @timecode += @offset
  end
  def next_slice?
    @slice.predecessor
  end
  def next_slice?
    @slice.successor
  end
  def go_prev_slice
    go_slice_begin
    @slice = @slice.predecessor
    @timecode -= @slice.duration
  end
  def go_next_slice
    go_slice_begin
    @slice = @slice.successor
    @timecode += @slice.duration
  end
  def seek(target_timecode)
    while target_timecode != @timecode
      if target_timecode < slice_begin
        if prev_slice?
          go_prev_slice
        else
          go_slice_begin
          break
        end
      elsif target_timecode >= slice_end
        if next_slice?
          go_next_slice
        else
          go_slice_end
          break
        end
      else
        @offset = target_timecode - slice_begin
        @timecode = target_timecode
      end
    end
    return @timecode
  end
end # class Position

AUDIO_DIR = "."

class StateMachineContext
  attr_accessor :fork, :pipe, :speed, :pos
  def initialize
    reset
  end
  def reset
    @fork = nil
    @pipe = nil
    @speed = 1.0
    @pos = Position.new
  end
end # class StateMachineContext

# forward declarations
class StateBase; end
class StateInitial < StateBase; end

class StateBase
  
  def initialize
  end
  
  #def method_missingXXX(method_name)
  #  warn "no such method: #{method_name}"
  #end
  
  def reset(ctx)
    ctx.reset
    StateInitial.instance
  end

  private
  def record_command(cmd, *args)
    puts "#{cmd} (#{args.join(', ')})"
  end
  def run_recorder(ctx)
    file = File.join(AUDIO_DIR, DateTime.now.strftime('%Y-%m-%d_%H-%M-%S_%L_%z'))
    new_slice = ASlice.new(file)
    ctx.pos.slice.insert(ctx.pos.offset, new_slice) if ctx.pos.slice
    ctx.pos.slice = new_slice
    ctx.pos.offset = 0
    ctx.pipe = IO.popen("rec '#{file}.mp3'", "r+")
    record_command(:record, file)
  end
  def stop_recorder(ctx)
    warn ctx.pipe.pid.inspect
    Process.kill("SIGINT", ctx.pipe.pid)

    file = ctx.pos.slice.file
    system("sox '#{file}' '#{reverse_filename(file)}' reverse") or warn "failed to create reverse file"
    
    ctx.pos.slice.update_duration
    ctx.pos.offset = ctx.pos.slice.duration
    ctx.pos.timecode += ctx.pos.slice.duration
    record_command(:seek, ctx.pos.timecode)
  end
  def pause_recorder(ctx)
    stop_recorder(ctx)
  end
  def resume_recorder(ctx)
    run_recorder(ctx)
  end
  def run_player(ctx)
    start_offset = ctx.pos.slice.offset + ctx.pos.offset
    file = ctx.pos.slice.file
    if ctx.speed > 0
      direction = :forward
    elsif ctx.speed < 0
      direction = :reverse
      file = reverse_filename(file)
    else
      warn "invalid speed value (0.0) when run_player"
      return
    end
    Thread.new do
      while true
        ctx.pipe = open("|mplayer -slave -quiet -af scaletempo -ss #{start_offset} -endpos #{ctx.pos.slice.duration} '#{file}'")
        if direction == :forward
          ctx.pos.go_slice_end
          if ctx.pos.slice.next_slice?
            ctx.pos.go_next_slide
            start_offset = 0.0
            file = ctx.pos.slice.file
          else
            break
          end
        else
          ctx.pos.go_slice_begin
          if ctx.pos.slice.prev_slice?
            ctx.pos.go_prev_slide
            start_offset = 0.0
            file = reverse_filename(ctx.pos.slice.file)
          else
            break
          end
        end # direction
      end # while-loop
    end # thread-block
  end # def run_player
  def stop_player(ctx)
    pause_player(ctx) # to adapt ctx.pos
    ctx.pipe << 'quit'
    record_command(:seek, ctx.pos.timecode)
  end
  def pause_player(ctx)
    flush_pipe(ctx.pipe)
    ctx.pipe << 'pausing get_time_pos'
    file_offset = ctx.pipe.gets.to_f * 1000
    if ctx.speed > 0
      ctx.pos.offset = file_offset - ctx.pos.slice.offset
      ctx.pos.offset = ctx.pos.slice.duration if ctx.pos.offset > ctx.pos.slice.duration - LATCH_TOLERANCE
      ctx.pos.timecode = ctx.pos.slice_begin + ctx.pos.offset
    elsif ctx.speed < 0
      ctx.pos.offset = ctx.pos.slice.offset + ctx.pos.slice.duration - file_offset
      ctx.pos.offset = 0 if ctx.pos.offset < LATCH_TOLERANCE
      ctx.pos.timecode = ctx.pos.slice_begin + ctx.pos.offset      
    else
    end
    record_command(:seek, ctx.pos.timecode)
  end
  def resume_player(ctx)
    ctx.pipe << 'pausing get_property pause'
    ctx.pipe << 'pause'
  end
  def speed_player(ctx, amount)
    if amount.abs < 0.01
      pause_player(ctx)
      ctx.speed = amount
      return
    end
    if amount > 0 and ctx.speed <= 0
      stop_player(ctx)
      run_player(ctx)
    elsif amount < 0 and ctx.speed >= 0
      stop_player(ctx)
      run_player(ctx, :reverse)
    else
      resume_player(ctx)
    end
    ctx.pipe << "speed_set #{amount.abs}"
    ctx.speed = amount
  end
  def reverse_filename(filename)
    filename.sub(/\.mp3$/, '.reverse.mp3')
  end
end # class StateBase

class StateInitial < StateBase
  include Singleton
  def record(ctx)
    run_recorder(ctx)
    StateRecording.instance
  end
  def load(ctx, record_filename)
    state_stopped = StateStopped.instance
    open(record_filename, "r") do |f|
      while l = f.gets
        case l
        when /^.* > record (.*)$/
          state_stopped.load($1)
        when /^.* > seek (.*)$/
          state_stopped.seek($1)
        else
          warn "ignoring line `#{l.chomp}'"
        end
      end
    end
    state_stopped
  end
end # class StateInitial

class StateRecording < StateBase
  include Singleton
  def pause(ctx)
    pause_recorder(ctx)
    StateRecordingPause.instance
  end
  def stop(ctx)
    stop_recorder(ctx)
    StateStopped.instance
  end
  def reset(ctx)
    stop_recorder(ctx)
    StateInitial.instance
  end
end # class StateRecording

class StateRecordingPause < StateBase
  include Singleton
  def resume(ctx)
    resume_recorder(ctx)
    StateRecording.instance
  end
  def stop(ctx)
    stop_recorder(ctx)
    StateStopped.instance
  end
  def reset(ctx)
    stop_recorder(ctx)
    StateInitial.instance
  end
end # class StateRecordingPause

class StatePlaying < StateBase
  include Singleton
  def pause(ctx)
    pause_player(ctx)
    StatePlayingPause.instance
  end
  def stop(ctx)
    stop_player(ctx)
    StateStopped.instance
  end
  def reset(ctx)
    stop_player(ctx)
    StateInitial.instance
  end
  def speed(ctx, arg, mode = :absolute)
    case arg
    when String
      case arg
      when /^+(.*)$/
        mode = :increase
      when /^-(.*)$/
        mode = :decrease
      else
        mode = :absolute
      end
      amount = $1 # XXX
      case arg
      when /^(\d+\.?\d*)%$/
        amount = $1.to_i * 0.01
      when /^\d+\.?|\d*\.\d+$/
        amount = $1.to_f
      else
        warn "invalid speed argument"
      end
    when Number
      amount = arg
    else
      warn "invalid argument"
      return
    end
    amount = case mode
             when :increase
               ctx.speed + amount
             when :decrease
               ctx.speed - amount
             when :absolute
               amount
             else
               raise
             end
    speed_player(ctx, amount)
  end
end # class StatePlaying

class StatePlayingPause < StateBase
  include Singleton
  def resume(ctx)
    resume_player(ctx)
    StatePlaying.instance
  end
  def stop(ctx)
    stop_player(ctx)
    StateStopped.instance
  end
  def reset(ctx)
    stop_player(ctx)
    StateInitial.instance
  end
end # class StatePlayingPause

class StateStopped < StateBase
  include Singleton
  def play(ctx)
    run_player(ctx)
    StatePlaying.instance
  end
  def record(ctx)
    run_recorder(ctx)
    StateRecording.instance
  end
  def set_marker(ctx, *args)
    # TODO args
    ctx.pos.slice.set_marker(ctx.pos.offset)
  end
  def load(ctx, slice_filename)
    new_slice = ASlice.new(slice_filename)
    new_slice.update_duration
    ctx.pos.slice.insert(ctx.pos.offset, new_slice)
    return self
  end
  def seek(ctx, timecode)
    ctx.pos.seek(timecode)
    return self
  end
  def delete(ctx, *args)
    # TODO
    raise "not yet implemented"
    ## TODO arguments
    #pos = ctx.pos
    #offset = pos.offset
    #slice = pos.slice
    #from_marker = slice.marker_before(offset)
    #to_marker = slice.marker_at_or_after(offset)
    #if from_marker and to_marker
    #  slice.delete(from_marker.offset, to_marker.offset)
    #end
  end
end

context = StateMachineContext.new
state = StateInitial.instance

keep_running = true

while keep_running
  cmd = STDIN.gets
  case cmd
  when /^\s*(#.*)?$/
    # comment => ignore
  when /^quit$/
    state = state.reset(context)
    keep_running = false
  when /^load (.*)$/
    state = state.reset(context)
    state = state.load(context, $1)
  when /^record$/
    state = state.record(context)
  when /delete( (.*))?/
    # TODO: optional arguments
    state = state.delete(context, $1)
  when /^play$/
    state = state.play(context)
  when /^stop$/
    state = state.stop(context)
  when /^pause$/
    state = state.pause(context)
  when /^resume$/
    state = state.resume(context)
  when /^speed (.*)$/
    state = state.speed(context, $1)
#  when /seek (.*)/
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
#    state = state.seek(amount, mode)
    
  when /set_marker( (.*))?/
    state = state.set_marker(context, $1)
  when /rm_marker( (.*))?/
    raise "not yet supported"
  else
    warn "unknown command: `#{cmd.chomp}'"
  end
end
