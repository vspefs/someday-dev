#include <print>
#include <SDL3/SDL.h>

int main()
{
    std::println("Linked SDL3 library version: {}", SDL_GetVersion());
}