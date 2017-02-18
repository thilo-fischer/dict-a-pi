// Copyright (c) 2016-2017  Thilo Fischer.
//
// This file is part of dictapi.
//
// dictapi is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// dictapi is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with tobak.  If not, see <http://www.gnu.org/licenses/>.

// g++ sdl-joystick.cpp -o sdl-joystick `sdl2-config --libs` `sdl2-config --cflags` && ./sdl-joystick

#include <stdio.h>
#include <assert.h>
#include <iostream>
#include <SDL.h>

// forward declarations (sort of)
class IState;
extern IState &state_default;
extern IState &state_initial;
extern IState &state_playing;
extern IState &state_recording_plain;
extern IState &state_recording_locked;
extern IState *current_state;

bool keep_running = true;

enum eButtons {
  BTN_DUMB,   // not in use
  BTN_PLAY,   // cue / playback, pause, lock recording
  BTN_RECORD, // record
  BTN_MARK,   // set marking
  BTN_RM_MARK,// remove marking
  BTN_DELETE, // delete
  BTN_LEFT,   // jmp previous marker
  BTN_RIGHT,  // jmp next marker
  BTN_PREV,   // previous slot
  BTN_NEXT,   // next slot
  BTN_QUIT,   // quit application
};

enum eDelete {
  DEL_INACTIVE,
  DEL_OPTION,
  DEL_ACK,
};
enum eDelete delete_state = DEL_INACTIVE;

Sint8 quit_btn_cnt = 0;
const Sint8 quit_btn_min = 3;

class IState {
public:
  virtual void process(eButtons button, bool button_press) = 0;
};

class BaseState : public IState {
public:
  /// dispatch to the according member function implemented by the child classes
  /// @param[in] button_press true if button was pressed down, false if button was released
  void process(eButtons button, bool button_press) {
    switch (button) {
    case BTN_DUMB:
      std::cerr << "Ignoring unused button event." << std::endl;      
      break;
    case BTN_PLAY:
      if (button_press)
        current_state = btn_press_play();
      else  
        current_state = btn_release_play();
      break;
    case BTN_RECORD:
      if (button_press)
        current_state = btn_press_record();
      else  
        current_state = btn_release_record();
      break;
    case BTN_MARK:
      if (button_press)
        current_state = btn_press_mark();
      else  
        current_state = btn_release_mark();
      break;
    case BTN_RM_MARK:
      if (button_press)
        current_state = btn_press_rm_mark();
      else  
        current_state = btn_release_rm_mark();
      break;
    case BTN_DELETE:
      if (button_press)
        current_state = btn_press_delete();
      else  
        current_state = btn_release_delete();
      break;
    case BTN_LEFT:
      if (button_press)
        current_state = btn_press_left();
      else  
        current_state = btn_release_left();
      break;
    case BTN_RIGHT:
      if (button_press)
        current_state = btn_press_right();
      else  
        current_state = btn_release_right();
      break;
    case BTN_PREV:
      if (button_press)
        current_state = btn_press_prev();
      else  
        current_state = btn_release_prev();
      break;
    case BTN_NEXT:
      if (button_press)
        current_state = btn_press_next();
      else  
        current_state = btn_release_next();
       break;
    case BTN_QUIT:
      if (button_press)
        current_state = btn_press_quit();
      else  
        current_state = btn_release_quit();
       break;
   default:
      std::cerr << "Unknown button: " << button << std::endl;
    }
  }
protected:
  virtual IState *btn_press_play() = 0;
  virtual IState *btn_release_play() = 0;
  virtual IState *btn_press_record() = 0;
  virtual IState *btn_release_record() = 0;
  virtual IState *btn_press_mark() = 0;
  virtual IState *btn_release_mark() = 0;
  virtual IState *btn_press_rm_mark() = 0;
  virtual IState *btn_release_rm_mark() = 0;
  virtual IState *btn_press_delete() = 0;
  virtual IState *btn_release_delete() = 0;
  virtual IState *btn_press_left() = 0;
  virtual IState *btn_release_left() = 0;
  virtual IState *btn_press_right() = 0;
  virtual IState *btn_release_right() = 0;
  virtual IState *btn_press_prev() = 0;
  virtual IState *btn_release_prev() = 0;
  virtual IState *btn_press_next() = 0;
  virtual IState *btn_release_next() = 0;
  virtual IState *btn_press_quit() = 0;
  virtual IState *btn_release_quit() = 0;
};

class StateDefault : public BaseState {
protected:
  IState *btn_press_play() {
    std::cout << "play" << std::endl;
    return &state_playing;
  }
  IState *btn_release_play() {
    return current_state;
  }
  IState *btn_press_record() {
    std::cout << "record" << std::endl;
    return &state_recording_plain;
  }
  IState *btn_release_record() {
    return current_state;
  }
  IState *btn_press_mark() {
    std::cout << "set_marker" << std::endl;
    return current_state;
  }
  IState *btn_release_mark() {
    return current_state;
  }
  IState *btn_press_rm_mark() {
    std::cout << "rm_marker" << std::endl;
    return current_state;
  }
  IState *btn_release_rm_mark() {
    return current_state;
  }
  IState *btn_press_delete() {
    switch (delete_state) {
    case DEL_INACTIVE:
      delete_state = DEL_OPTION;
      break;
    case DEL_OPTION:
      delete_state = DEL_ACK;
      std::cout << "delete" << std::endl;
      break;
    default:
      std::cerr << "Invalid Program State: " << __FILE__ << ":" << __LINE__;
    }
    return current_state;
  }
  IState *btn_release_delete() {
    switch (delete_state) {
    case DEL_OPTION:
      delete_state = DEL_INACTIVE;
      break;
    case DEL_ACK:
      delete_state = DEL_OPTION;
      break;
    default:
      std::cerr << "Invalid Program State: " << __FILE__ << ":" << __LINE__;
    }
    return current_state;
  }
  IState *btn_press_left() {
    std::cout << "# todo" << std::endl;
    return current_state;
  }
  IState *btn_release_left() {
    return current_state;
  }
  IState *btn_press_right() {
    std::cout << "# todo" << std::endl;
    return current_state;
  }
  IState *btn_release_right() {
    return current_state;
  }
  IState *btn_press_prev() {
    std::cout << "# todo" << std::endl;
    return current_state;
  }
  IState *btn_release_prev() {
    return current_state;
  }
  IState *btn_press_next() {
    std::cout << "# todo" << std::endl;
    return current_state;
  }
  IState *btn_release_next() {
    return current_state;
  }
  IState *btn_press_quit() {
    ++quit_btn_cnt;
    if (quit_btn_cnt >= quit_btn_min) {
      keep_running = false;
      std::cout << "quit" << std::endl;
    }
    return current_state;
  }
  IState *btn_release_quit() {
    --quit_btn_cnt;
    if (quit_btn_cnt < 0)
      quit_btn_cnt = 0;
    return current_state;
  }
};
StateDefault state_default_instance;

class StateInitial : public StateDefault {
protected:
  // disable marker and delete buttons for StateInitial
  IState *btn_press_mark() {
    return current_state;
  }
  IState *btn_press_delete() {
    return current_state;
  }
  IState *btn_release_delete() {
    return current_state;
  }
};
StateInitial state_initial_instance;

class StatePlaying : public StateDefault {
protected:
  IState *btn_press_play() {
    std::cout << "pause" << std::endl;
    return &state_default;
  }
};
StatePlaying state_playing_instance;

class StateRecordingPlain : public StateDefault {
  IState *btn_press_play() {
    return &state_recording_locked;
  }  
  IState *btn_release_record() {
    std::cout << "pause" << std::endl;
    return &state_default;
  }
};
StateRecordingPlain state_recording_plain_instance;

class StateRecordingLocked : public StateDefault {
  IState *btn_press_play() {
    std::cout << "stop" << std::endl;
    return &state_default;
  }  
  IState *btn_press_record() {
    std::cout << "pause" << std::endl;
    return current_state;
  }
  IState *btn_release_record() {
    std::cout << "resume" << std::endl;
    return current_state;
  }
};
StateRecordingLocked state_recording_locked_instance;

IState &state_default = state_default_instance;
IState &state_initial = state_initial_instance;
IState &state_playing = state_playing_instance;
IState &state_recording_plain = state_recording_plain_instance;
IState &state_recording_locked = state_recording_locked_instance;

IState *current_state = &state_initial;


void axis_nop(Sint16 value) {
  fprintf(stderr, "# nop\n"); // TODO for debugging only -> remove
}

void slow_pb_axis_motion(Sint16 value) {
  double fraction = ((double) value) / 32767;
  printf("%s %f\n", "speed", fraction); 
}

void fast_pb_axis_motion(Sint16 value) {
  static const double MAX_PB_SPEED = 16;
  double fraction = MAX_PB_SPEED * ((double) value) / 32767;
  printf("%s %f\n", "speed", fraction); 
}


typedef void (*axis_fct)(Sint16 value);

// Button Mapping
//  for X-Box 360 pad compatible devices

const eButtons btn_mapping[] = {
  /* 0: A grn*/ BTN_PLAY,
  /* 1: B red*/ BTN_RECORD,
  /* 2: X blu*/ BTN_MARK,
  /* 3: Y ylw*/ BTN_RM_MARK,
  /* 4: L I  */ BTN_DELETE,
  /* 5: R I  */ BTN_DELETE,
  /* 6: back */ BTN_QUIT,
  /* 7: start*/ BTN_QUIT,
  /* 8: mode */ BTN_QUIT,
  /* 9: anaL */ BTN_DUMB,
  /*10: anaR */ BTN_DUMB,
};
const size_t btn_mapping_cnt = sizeof(btn_mapping)/sizeof(btn_mapping[0]);

// A: Analog Stick
// L: Left; R: Right
// H: Horizontal; V: Vertical
const axis_fct axis_funcs[] = {
  /* 0: ALH  */ fast_pb_axis_motion,
  /* 1: ALV  */ axis_nop,
  /* 2: L II */ axis_nop,
  /* 3: ARH  */ slow_pb_axis_motion,
  /* 4: ARV  */ axis_nop,
  /* 5: R II */ axis_nop,
};
const size_t axis_funcs_cnt = sizeof(axis_funcs)/sizeof(axis_funcs[0]);

const eButtons hat_mapping[] = {
  /* 1: up  */ BTN_PREV,
  /* 2: rgt */ BTN_RIGHT,
  /* 4: dn  */ BTN_NEXT,
  /* 8: lft */ BTN_LEFT,
};
const size_t hat_mapping_cnt = sizeof(hat_mapping)/sizeof(hat_mapping[0]);

Sint8 hat_state = 0;

int main(int argc, char *argv[]) {
  // SDL2 will only report events when the window has focus, so set
  // this hint as we don't have a window
  //SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");

  if (SDL_Init(SDL_INIT_JOYSTICK | SDL_INIT_GAMECONTROLLER) < 0) {
    fprintf(stderr, "Unable to initialize SDL joystick/gamecontroller subsystem: %s\n", SDL_GetError());
    return -1;
  }

  int js_count = SDL_NumJoysticks();
  if (js_count < 1) {
    fprintf(stderr, "No Joysticks found: %s\n", SDL_GetError());
    return -1;
  } else if (js_count > 1) {
    fprintf(stderr, "%d joysticks found -- ambiguous.\n", js_count);
    return -1;
  }
	
  SDL_Joystick *js = SDL_JoystickOpen(0);
  if (js == NULL ) {
    fprintf(stderr, "failed to open joystick: %s\n", SDL_GetError());
    return -1;
  }

  SDL_Event event;

  // flush all initial events
  while (SDL_PollEvent(&event)) {}
  
  fprintf(stderr, "connected device: %s\n", SDL_JoystickName(js));
  fprintf(stderr, "buttons: %d\n", SDL_JoystickNumButtons(js));
  fprintf(stderr, "axes: %d\n", SDL_JoystickNumAxes(js));
  fprintf(stderr, "hats: %d\n", SDL_JoystickNumHats(js));

  keep_running = true;
  while(keep_running) {
    SDL_Delay(5);

    while (SDL_PollEvent(&event)) {
      switch(event.type) {
      case SDL_JOYAXISMOTION:
        fprintf(stderr, "axis: %d, value: %d\n", event.jaxis.axis, event.jaxis.value);
        if (event.jaxis.axis < axis_funcs_cnt) {
          axis_funcs[event.jaxis.axis](event.jaxis.value);
        }
        break;

      case SDL_JOYBUTTONDOWN:
        fprintf(stderr, "btn DN: %d\n", event.jbutton.button);
        if (event.jbutton.button < btn_mapping_cnt) {
          current_state->process(btn_mapping[event.jbutton.button], true);
        }
        break;
      case SDL_JOYBUTTONUP:
        fprintf(stderr, "btn UP: %d\n", event.jbutton.button);
        if (event.jbutton.button < btn_mapping_cnt) {
          current_state->process(btn_mapping[event.jbutton.button], false);
        }
        break;
      case SDL_JOYHATMOTION:
        if (event.jhat.hat == 0) {
          fprintf(stderr, "hat: %d value: %d\n", event.jhat.hat, event.jhat.value);
          Sint8 diff = hat_state ^ event.jhat.value;
          for (int i = 0; i < 4; ++i) {
            if (diff & (1 << i)) {
              if (event.jhat.value & (1 << i)) {
                fprintf(stderr, "hat btn %d dn\n", i);
                current_state->process(hat_mapping[i], true);
              } else {
                fprintf(stderr, "hat btn %d up\n", i);
                current_state->process(hat_mapping[i], false);
              }   
            }
          }
          hat_state = event.jhat.value;
        } else {
          fprintf(stderr, "multiple hats not (yet) supported, ignoring hat %d.\n", event.jhat.hat);
        }
        break;       
      case SDL_QUIT:
        keep_running = false;
        break;

      default:
        fprintf(stderr, "Error: Unhandled event type: %d\n", event.type);
      }
    }
  }
  return 0;
}
