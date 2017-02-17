// http://de.wikibooks.org/wiki/SDL:_Joystick
// gcc sdl-joystick.c -o sdl-joystick `sdl-config --libs` `sdl-config --cflags`
// based on https://lastlog.de/wiki/index.php/SDL-joystick

#include <stdio.h>
#include <stdbool.h>
#include <SDL.h>

void btn_nop() {
  printf("# nop\n"); // TODO for debugging only -> remove
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

void speed_axis_motion(Sint16 value) {
  double fraction = ((double) value) / 32767;
  printf("%s %f\n", "speed", fraction); 
}


typedef void (*btn_fct)();
typedef void (*axis_fct)(Sint16 value);

const btn_fct btn_dn_funcs[] = {
  rec_btn_dn,
  play_btn_dn,
  mark_btn_dn,
};
const size_t btn_dn_funcs_cnt = sizeof(btn_dn_funcs)/sizeof(btn_dn_funcs[0]);

const btn_fct btn_up_funcs[] = {
  rec_btn_up,
  play_btn_up,
  btn_nop,
  delete_btn_up,
};
const size_t btn_up_funcs_cnt = sizeof(btn_up_funcs)/sizeof(btn_up_funcs[0]);

const axis_fct axis_funcs[] = {
  speed_axis_motion,
};
const size_t axis_funcs_cnt = sizeof(axis_funcs)/sizeof(axis_funcs[0]);


int main(int argc, char *argv[]) {
  if (SDL_InitSubSystem(SDL_INIT_JOYSTICK) < 0) {
    fprintf(stderr, "Unable to initialize SDL joystick subsystem: %s\n", SDL_GetError());
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

  printf ( "%i achsen\n", SDL_JoystickNumAxes ( js ) );
  printf ( "%i rollbaelle\n", SDL_JoystickNumBalls ( js ) );
  printf ( "%i heads\n", SDL_JoystickNumHats ( js ) );
  printf ( "%i koepfe\n", SDL_JoystickNumButtons ( js ) );

  bool keep_running = true;
  while(keep_running) {
    SDL_Delay(2);
    SDL_Event event;

    while (SDL_PollEvent(&event)) {
      switch(event.type) {
      case SDL_JOYAXISMOTION:
        if (event.jaxis.axis < axis_funcs_cnt) {
          axis_funcs[event.jaxis.axis](event.jaxis.value);
        }
        break;

      case SDL_JOYBUTTONDOWN:
         if (event.jbutton.button < btn_dn_funcs_cnt) {
           btn_dn_funcs[event.jbutton.button]();
         }
         break;
     case SDL_JOYBUTTONUP:
         if (event.jbutton.button < btn_up_funcs_cnt) {
           btn_up_funcs[event.jbutton.button]();
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
