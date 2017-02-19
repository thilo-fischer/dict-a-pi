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

# path where to store recorded audio files
AUDIO_DIR = "."

# time in milliseconds allowed to round to get to audio slice edges or markers
LATCH_TOLERANCE = 200

# must be file extension recognized by sox
FILE_FORMAT = "mp3"

def dbg(*args)
  warn "#{DateTime.now.strftime('%H-%M-%S_%L')}: #{args}"
end

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
  def find_marker(offset)
    result = {}
    return result if @markers.empty?
    geq_idx = @markers.find_index {|m| m.offset >= offset-LATCH_TOLERANCE}
    if geq_idx
      geq = @markers[geq_idx]
      if geq.offset >= offset-LATCH_TOLERANCE and geq.offset <= offset+LATCH_TOLERANCE
        result[:accurate] = geq
        result[:previous] = @markers[geq_idx - 1] if geq_idx - 1 >= 0
        result[:next    ] = @markers[geq_idx + 1] if geq_idx + 1 <  @markers.length
        return result
      #elsif geq.offset < offset
      #  raise "programming error" # => should never get here ...
      #  result[:previous] = geq
      #  result[:next    ] = @markers[geq_idx + 1] if geq_idx + 1 <  @markers.length
      #  return result
      elsif geq.offset > offset
        result[:previous] = @markers[geq_idx - 1] if geq_idx - 1 >= 0
        result[:next    ] = geq
        return result
      else
        raise "programming error"
      end
    else
      result[:previous] = @markes.first
    end
  end
  def update_duration
    `soxi '#{file}'`.lines.find {|l| l =~ /^Duration\s*:\s*(\d+):(\d\d):(\d\d).(\d+)/}
    @duration = (($1.to_i * 60 + $2.to_i) * 60 + $3.to_i) * 1000 + ($4 + "000")[0..2].to_i
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

##
# Not a State the state machine should ever enter. Base class that
# implements the methods that provide the actual operations to be used
# by the chlid classes that implement the actual states.  This would
# be an abstract class if one could have abstact classes in Ruby.
class StateBase
  
  def method_missing(method_name, *args)
    warn "invalid operation `#{method_name}' for current state `#{self}'"
    self
  end
  
  # methods to be implemented by child classes:
  # play
  # record
  # pause
  # resume
  # stop
  # speed
  # seek
  # seek_marker
  # set_marker
  # rm_marker
  # delete
  # reset
  # load

  private
  # helper methods
  # XXX move to separate class or to module? (If moving to module: make classes including the module implicitly include +Singleton+??)
  def record_command(cmd, *args)
    puts "#{cmd} (#{args.join(', ')})"
  end
  def run_recorder(ctx)
    file = File.join(AUDIO_DIR, "#{DateTime.now.strftime('%Y-%m-%d_%H-%M-%S_%L_%z')}.#{FILE_FORMAT}")
    new_slice = ASlice.new(file)
    ctx.pos.slice.insert(ctx.pos.offset, new_slice) if ctx.pos.slice
    ctx.pos.slice = new_slice
    ctx.pos.offset = 0
    ctx.pipe = IO.popen("rec '#{file}'", "r+")
    record_command(:record, file)
  end
  def stop_recorder(ctx)
    dbg "stop recorder with PID #{ctx.pipe.pid.inspect}"
    Process.kill("SIGINT", ctx.pipe.pid)

    file = ctx.pos.slice.file
    dbg "polling for file `#{file}' ..."
    sleep(0.1) until File.exist?(file)
    dbg "=> file `#{file}' exists"

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
    if (ctx.pipe)
      if amount.abs < 0.1
        pause_player(ctx)
        ctx.speed = amount
        return
      end
      # change playback direction if speed changes from negative to positive value or vice verse
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
    end
    ctx.speed = amount
  end
  def reverse_filename(filename)
    filename.sub(/\.#{FILE_FORMAT}$/, ".reverse.#{FILE_FORMAT}")
  end
end # class StateBase

##
# System starts in this state and enters this state after every
# loading of another file.
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
  def reset(ctx)
    self
  end
end # class StateInitial

class StateDefault < StateBase
  include Singleton
  def play(ctx)
    run_player(ctx)
    StatePlaying.instance
  end
  def record(ctx)
    run_recorder(ctx)
    StateRecording.instance
  end
  # missing methods invalid for this state:
  # pause
  # resume
  # stop
  def speed(ctx, value, mode = :absolute)
    abs_value = case mode
                when :relative
                  ctx.speed + value
                when :absolute
                  value
                else
                  raise
                end
    speed_player(ctx, value)
  end
  def seek(ctx, position, mode = :absolute)
    new_state = stop(ctx)
    abs_pos = case mode
              when :absolute
                position
              when :relative
                ctx.pos.timecode + position
              when :end_offset
                raise "not yet implemented"
              else
                raise "programming error"
              end
    ctx.pos.seek(abs_pos)
    new_state
  end
  # If count is > 0, seek to position of count'th next marker.
  # If count is < 0, seek to position of count'th previous marker.
  # If count is == 0, seek to position of nearest marker.
  def seek_marker(ctx, count)
    pos = ctx.pos

    raise "programming error" if pos.timecode < pos.slice_begin or pos.timecode > pos.slice_end

    slice_marks = pos.slice.find_marker(pos.offset)

    if count == 0 and slice_marks.key?(:accurate)
      return seek(ctx, pos.slice_begin + slice_marks[:accurate].offset)
    end

    prev_mark = nil
    prev_mark_timecode = nil
    prev_mark_slice = pos.slice
    prev_mark_slice_begin = pos.slice_begin
    if count <= 0
      if slice_marks.key?(:prev)
        prev_mark = slice_marks(:prev)
      else
        while prev_mark == nil do
          prev_mark_slice = @prev_mark_slice.predecessor
          break if prev_mark_slice == nil
          prev_mark_slice_begin -= prev_mark_slice.duration
          prev_mark = prev_mark_slice.markers.last unless prev_mark_slice.markers.empty?
        end
      end
    end
    prev_mark_timecode = prev_mark_slice_begin + prev_mark.offset if prev_mark

    next_mark = nil
    next_mark_timecode = nil
    next_mark_slice = pos.slice
    next_mark_slice_begin = pos.slice_begin
    if count >= 0
      if slice_marks.key?(:next)
        next_mark = slice_marks(:next)
      else
        while next_mark == nil do
          next_mark_slice_begin += next_mark_slice.duration
          next_mark_slice = @next_mark_slice.successor
          break if next_mark_slice == nil
          next_mark = next_mark_slice.markers.first unless next_mark_slice.markers.empty?
        end
      end
    end
    next_mark_timecode = next_mark_slice_begin + next_mark.offset if next_mark

    if count == 0
      if prev_mark
        if next_mark
          if pos.timecode - prev_mark_timecode <= next_mark_timecode - pos.timecode
            return seek(ctx, prev_mark_timecode)
          else
            return seek(ctx, next_mark_timecode)
          end
        else
          return seek(ctx, prev_mark_timecode)
        end
      else
        if next_mark
          return seek(ctx, next_mark_timecode)
        else
          warn "seek_marker failed, no marker found"
          return self
        end
      end
    elsif count > 0
      if next_mark
        # FIXME allow to seek over more than just one marker
        return seek(ctx, next_mark_timecode)
      else
        return seek(ctx, 0, :end_offset)
      end
    elsif count < 0
      if prev_mark
        # FIXME allow to seek over more than just one marker
        return seek(ctx, prev_mark_timecode)
      else
        return seek(ctx, 0, :absolute)
      end      
    else
      raise "programming error"
    end
    self
  end # def seek_marker
  def set_marker(ctx, *args)
    # TODO args
    ctx.pos.slice.set_marker(ctx.pos.offset)
    self
  end
  def rm_marker(ctx, *args)
    warn "TODO not yet implemented"
    self
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
  def reset(ctx)
    ctx.reset
    StateInitial.instance
  end
end # class StateDefault

class StatePlaying < StateDefault
  include Singleton
  def play(ctx)
    self
  end
  def record(ctx)
    stop(ctx).record(ctx)
  end
  def pause(ctx)
    pause_player(ctx)
    StatePlayingPause.instance
  end
  def stop(ctx)
    stop_player(ctx)
    StateStopped.instance
  end
  def seek(ctx, *args)
    # TODO args
    pause_player(ctx)
    super
    resume_player(ctx)
    self
  end
  def seek_marker(ctx, count)
    # TODO args
    pause_player(ctx)
    super
    resume_player(ctx)
    self
  end
  def set_marker(ctx, *args)
    # TODO args
    pause_player(ctx)
    super
    resume_player(ctx)
    self
  end
  def delete(ctx)
    stop(ctx).delete(ctx)
  end
  def reset(ctx)
    stop_player(ctx)
    super
  end
end # class StatePlaying

class StatePlayingPause < StateDefault
  include Singleton
  def play(ctx)
    resume_player(ctx)
    StatePlaying.instance
  end
  def record(ctx)
    stop(ctx).record(ctx)
  end
  def pause(ctx)
    return self
  end
  def resume(ctx)
    resume_player(ctx)
    StatePlaying.instance
  end
  def stop(ctx)
    stop_player(ctx)
    StateStopped.instance
  end
  def delete(ctx)
    stop(ctx).delete(ctx)
  end
  def reset(ctx)
    stop_player(ctx)
    super
  end
end # class StatePlayingPause

class StateRecording < StateDefault
  include Singleton
  def play(ctx)
    stop(ctx).play(ctx)
  end
  def record(ctx)
    self
  end
  def pause(ctx)
    pause_recorder(ctx)
    StateRecordingPause.instance
  end
  def stop(ctx)
    stop_recorder(ctx)
    StateStopped.instance
  end
  def set_marker(ctx, *args)
    warn "TODO not yet implemented"
    #ctx.pos.slice.set_marker(ctx.pos.offset)
    self
  end
  def delete(ctx)
    stop(ctx).delete(ctx)
  end
  def reset(ctx)
    stop_recorder(ctx)
    super
  end
end # class StateRecording

class StateRecordingPause < StateDefault
  include Singleton
  def play(ctx)
    stop(ctx).play(ctx)
  end
  def record(ctx)
    resume_recorder(ctx)
    StateRecording.instance
  end
  def pause(ctx)
    self
  end
  def resume(ctx)
    resume_recorder(ctx)
    StateRecording.instance
  end
  def stop(ctx)
    stop_recorder(ctx)
    StateStopped.instance
  end
  def delete(ctx)
    stop(ctx).delete(ctx)
  end
  def reset(ctx)
    stop_recorder(ctx)
    super
  end
end # class StateRecordingPause

class StateStopped < StateDefault
  include Singleton
  def stop(ctx)
    return self
  end
  def load(ctx, slice_filename)
    new_slice = ASlice.new(slice_filename)
    new_slice.update_duration
    ctx.pos.slice.insert(ctx.pos.offset, new_slice)
    return self
  end
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
