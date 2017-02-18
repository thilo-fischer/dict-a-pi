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

#include <stdbool.h>
#include <stdio.h>
#include <assert.h>
#include <SDL.h>

enum buttons {
  B_PLAY,  // cue / playback, pause, lock recording
  B_REC,   // record
  B_MARK,  // set marking
  B_DEL,   // delete
  B_LEFT,  // jmp previous marker
  B_RIGHT, // jmp next marker
  B_UP,    // next slot
  B_DOWN,  // previous slot
  B_LAST_ELEMENT
};

enum button_state {
  BS_DOWN, // button press
  BS_UP,   // button release
};


struct state;

typedef const struct state *(*state_transition)();

struct state {
  state_transition transitions[B_LAST_ELEMENT];
};

const struct state *trans_start_playback();
const struct state *trans_start_record();
const struct state *trans_set_mark();

const struct state state_initial = {
  .transitions = {
    [B_PLAY] = trans_start_playback,
    [B_REC]  = trans_start_record,
    [B_MARK] = trans_set_mark,
    //[B_DEL]  = trans_delete,
  }
};

const struct state *current_state = &state_initial;

const struct state *trans_start_playback() {
  printf("%s\n", "play");
  return &state_initial;
}

const struct state *trans_start_record() {
  printf("%s\n", "record");
  return &state_initial;
}

const struct state *trans_set_mark() {
  printf("%s\n", "set_marker");
  return current_state;
}


void btn_nop() {
  fprintf(stderr, "# nop\n"); // TODO for debugging only -> remove
}

void rec_btn_dn() {
  printf("%s\n", "record");
}

void rec_btn_up() {
  printf("%s\n", "pause");
}

void play_btn_dn() {
  printf("%s\n", "play");
}

void play_btn_up() {
  printf("%s\n", "pause");
}

void mark_btn_dn() {
  printf("%s\n", "set_marker");
}

void delete_btn_up() {
  printf("%s\n", "delete");
}

void axis_nop(Sint16 value) {
  fprintf(stderr, "# nop\n"); // TODO for debugging only -> remove
}

void speed_axis_motion(Sint16 value) {
  double fraction = ((double) value) / 32767;
  printf("%s %f\n", "speed", fraction); 
}


typedef void (*btn_fct)();
typedef void (*axis_fct)(Sint16 value);

// Button Mapping
//  for X-Box 360 pad compatible devices

const btn_fct btn_dn_funcs[] = {
  /* 0: A grn*/ play_btn_dn,
  /* 1: B red*/ rec_btn_dn,
  /* 2: X blu*/ btn_nop,
  /* 3: Y ylw*/ mark_btn_dn,
  /* 4: L I  */ btn_nop,
  /* 5: R I  */ btn_nop,
  /* 6: back */ btn_nop,
  /* 7: start*/ btn_nop,
  /* 8: mode */ btn_nop,
  /* 9: anaL */ btn_nop,
  /*10: anaR */ btn_nop,
};
const size_t btn_dn_funcs_cnt = sizeof(btn_dn_funcs)/sizeof(btn_dn_funcs[0]);

const btn_fct btn_up_funcs[] = {
  /* 0: A grn*/ play_btn_up,
  /* 1: B red*/ rec_btn_up,
  /* 2: X blu*/ delete_btn_up,
  /* 3: Y ylw*/ btn_nop,
  /* 4: L I  */ btn_nop,
  /* 5: R I  */ btn_nop,
  /* 6: back */ btn_nop,
  /* 7: start*/ btn_nop,
  /* 8: mode */ btn_nop,
  /* 9: anaL */ btn_nop,
  /*10: anaR */ btn_nop,
};
const size_t btn_up_funcs_cnt = sizeof(btn_up_funcs)/sizeof(btn_up_funcs[0]);

// A: Analog Stick
// L: Left; R: Right
// H: Horizontal; V: Vertical
const axis_fct axis_funcs[] = {
  /* 0: ALH  */ axis_nop,
  /* 1: ALV  */ axis_nop,
  /* 2: L II */ axis_nop,
  /* 3: ARH  */ speed_axis_motion,
  /* 4: ARV  */ axis_nop,
  /* 5: R II */ axis_nop,
};
const size_t axis_funcs_cnt = sizeof(axis_funcs)/sizeof(axis_funcs[0]);

const btn_fct hat_dn_funcs[] = {
  /* 1: up  */ btn_nop,
  /* 2: rgt */ btn_nop,
  /* 4: dn  */ btn_nop,
  /* 8: lft */ btn_nop,
};
const size_t hat_dn_funcs_cnt = sizeof(hat_dn_funcs)/sizeof(hat_dn_funcs[0]);

const btn_fct hat_up_funcs[] = {
  /* 1: up  */ btn_nop,
  /* 2: rgt */ btn_nop,
  /* 4: dn  */ btn_nop,
  /* 8: lft */ btn_nop,
};
const size_t hat_up_funcs_cnt = sizeof(hat_up_funcs)/sizeof(hat_up_funcs[0]);

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

  bool keep_running = true;
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
        if (event.jbutton.button < btn_dn_funcs_cnt) {
          btn_dn_funcs[event.jbutton.button]();
        }
        break;
      case SDL_JOYBUTTONUP:
        fprintf(stderr, "btn UP: %d\n", event.jbutton.button);
        if (event.jbutton.button < btn_up_funcs_cnt) {
          btn_up_funcs[event.jbutton.button]();
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
                hat_dn_funcs[i]();
              } else {
                fprintf(stderr, "hat btn %d up\n", i);
                hat_up_funcs[i]();
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
