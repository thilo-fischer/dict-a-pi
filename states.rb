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
