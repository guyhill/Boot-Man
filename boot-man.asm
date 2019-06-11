; Boot-Man
;
; (c) 2019 Guido van den Heuvel
;
; Boot-Man is a Pac-Man clone that fits (snugly) inside the Master Boot Record of a USB stick.
; A USB stick with Boot-Man on it boots into the game (hence the name). Unfortunately, however,
; Boot-Man leaves no room in the MBR for a partition table, which means that a USB stick with Boot-Man
; in its MBR cannot be used to store data. In fact, Windows does not recognize a USB stick with 
; Boot-Man in its MBR as a valid storage medium.
;
; Controls of the game: you control Boot-Man using the WASD keys. No other user input is necessary. Some other
; keys can also be used to control Boot-Man, this is a side effect of coding my own keyboard handler in 
; just a few bytes. There simply wasn't room for checking the validity of every key press.
;
; The game starts automatically, and when Boot-Man dies, a new game starts automatically within a couple of seconds.
;
;
; I've had to take a couple of liberties with the original Pac-Man game to fit Boot-Man inside the 510
; bytes available in the MBR:
;
; * The ghosts start in the four corners of the maze, they do not emerge from a central cage like in the original
;
; * There's just a single level. If you finish the level, the game keeps running with an empty maze. While 
;   it is rather difficult to finish the game (which is intentional, because of the single level), it is possible. 
;
; * Boot-Man only has 1 life. If Boot-Man dies, another game is started automatically (by re-reading the MBR
;   from disk, there simply isn't enough room to re-initialize the game in any other way)
;
; * Power pills function differently from the original. When Boot-Man eats a power pill, all ghosts become
;   ethereal (represented in game by just their eyes being visible) and cease to chase Boot-Man. While ethereal,
;   Boot-Man can run through ghosts with no ill effects. While I would really like to include the "ghost eating"
;   from the original, which I consider to be an iconic part of the game, this simply isn't possible in the little
;   space available.
;
; * There's no score, and no fruit to get bonus points from.
; 
; * All ghosts, as well as Boot-Man itself, have the same, constant movement speed. In the original, the ghosts
;   run at higher speeds than Pac-Man, while Pac-Man gets delayed slightly when eating and ghosts get delayed when moving
;   through the tunnel connecting both sides of the maze. This leads to very interesting dynamics and strategies
;   in the original that Boot-Man, by necessity, lacks.
;
;
; Boot-Man runs in text mode. It uses some of the graphical characters found in IBM codepage 437 for its objects:
;   - Boot-Man itself is represented by the smiley face (☻), which is character 0x02 in the IBM charset
;   - The Ghosts are represented by the infinity symbol (∞), which is character 0xec. These represent
;     a ghost's eyes, with the ghost's body being represented simply by putting the character on a 
;     coloured background
;   - The dots that represent Boot-Man's food are represented by the bullet character (•), 
;     which is character 0xf9
;   - The power pills with which Boot-Man gains extra powers are represented by the diamond (♦),
;     which is character 0x04
;   - The walls of the maze are represented by the full block character (█), which is character 0xdb
;
; Boot-Man runs off int 8, which is connected to the timer interrupt. It should therefore run at the same speed
; on all PCs. It includes its own int 9 (keyboard) handler. The code is quite heavily optimized for size, so
; code quality is questionable at best, and downright atrocious at worst.


org 0x7c00                          ; The MBR is loaded at 0x0000:0x7c00 by the BIOS
bits 16                             ; Boot-Man runs in Real Mode. I am assuming that the BIOS leaves the CPU is Real Mode.
                                    ; This is true for the vast majority of PC systems. If your system's BIOS
                                    ; switches to Protected Mode or Long Mode during the boot process, Boot-Man
                                    ; won't run on your machine.

start:
    cli                             ; Disable interrupts, as we are going to set up interrupt handlers and a stack
    xor ax, ax          
    mov ds, ax                      ; Set up a data segment that includes the Interrupt Vector Table and the Boot-Man code
    mov [bootdrive], dl             ; save the current drive number, which has been stored in dl by the BIOS
    mov ss, ax          
    mov sp, 0x28                    ; Set up a temporary stack, within the interrupt vector table
    push ax                         ; This saves some bytes when setting up interrupt vectors
    push word int9handler           ; Set up my own int 9 (keyboard) handler
    push ax
    push word int8handler           ; Set up my own int 8 (timer interrupr) handler
    
    mov sp, ax                      ; Set up the real stack.

    inc ax                          ; int 0x10 / ah = 0: Switch video mode. Switch mode to 40x25 characters (al = 1). 
    int 0x10                        ; In this mode, characters are approximately square, which means that horizontal 
                                    ; and vertical movement speeds are almost the same.

    mov cx, 0x2000                  ; int 0x10 / ah = 1: Determine shape of hardware cursor. 
    mov ah, 0x01                    ; With cx = 0x2000, this removes the hardware cursor from the screen altogether
    int 0x10


    cld                             ; Clear the direction flag. We use x86 string instructions a lot as they have one-byte codes
    mov ax, 0xb800
    mov es, ax                      ; Set up the es segment to point to video RAM


;-----------------------------------------------------------------------------------------------------
; buildmaze: builds the maze. The maze is stored in memory as a bit array, with 1 representing a wall
;            and 0 representing a food dot. Since the maze is left-right symmetrical, only half of the
;            maze is stored in memory. The positions of the power pills is hard-coded in the code.
;            Adding the power pills to the bit array would have necessitated 2 bits for every 
;            character, increasing its size drastically.
;
;            Both sides of the maze are drawn simultaneously. The left part is drawn left to right,
;            while the right part is drawn right to left. For efficiency reasons, the entire maze 
;            is built from the bottom up. Therefore, the maze is stored upside down in memory
;-----------------------------------------------------------------------------------------------------
buildmaze:
    mov di, 0x0788                  ; Lower left corner of maze in video ram
    mov si, maze                    ; The first byte of the bit array containing the maze
    mov dx, 0x05fa                  ; Address in video ram of the lower left powerpill
.maze_outerloop:
    mov cx, 0x003c                  ; The distance between a character in the maze and its 
                                    ; symmetric counterpart. Also functions as loop counter
    lodsw                           ; Read 16 bits from the bit array, which represents one
                                    ; 32 character-wide row from the maze
.maze_innerloop:
    shl ax, 1                       ; shift out a single bit to determine whether a wall or dot must be shown
    push ax
    mov ax, 0x01db                  ; Assume it is a wall character (blue solid block)
    jc .draw                        ; Draw the character if a 1 was shifted out
    mov ax, 0x0ff9                  ; otherwise, assume a food character (white bullet)
    cmp di, dx                      ; See if instead of food we need to draw a power pill
    jnz .draw                       
    mov dh, 0x00                    ; Update powerpill address to draw remaining powerpills
    mov al, 0x04                    ; powerpill character (white diamond - no need to set up colour once more)
.draw:
    stosw                           ; Store character + colour in video ram
    push di
    add di, cx                      ; Go to its symmetric counterpart
    stosw                           ; and store it as well
    pop di
    pop ax
    sub cx, 4                       ; Update the distance between the two sides of the maze
    jns .maze_innerloop             ; As long as the distance between the two halves is positive, we continue

    sub di, 0x70                    ; Go to the previous line on the screen in video RAM. 
    jns .maze_outerloop             ; Keep going as long as this line is on screen.


    sti                             ; Initialization is complete, hence we can enable interrupts

.end:                               ; Idle loop, as everything else is done in the interrupt handlers.
                                    ; Unfortunately there's no room for a hlt here so the CPU keeps running 100%.
    mov al, 0x20                    ; Continuously write "end of interrupt". This saves a few bytes in the 
    out 0x20, al                    ; interrupt handlers themselves, as we have to do it only once, here.
    jmp .end                        ; Overall, not a good way to implement an idle loop, its only saving grace 
                                    ; being that it is so short.


int8handler:
    pusha
    mov si, bootman_data
    dec byte [si + pace_offset]
jump_size: equ $ + 1                
    jz .move_all                    ; This jump offset is overwritten when boot-man dies
    popa
    iret

    push ds                         ; The new offset points here.
    pop es                          ; This code reloads the MBR and jumps back to the start
    mov ax, 0x0201
    mov cx, 0x0001
bootdrive: equ $ + 1
    mov dx, 0x0080
    mov bx, 0x7c00
    int 0x13
    jmp start

.move_all:
    mov byte [si + pace_offset], 0x3

    ; Move boot-man
    mov al, [si + 3]
    mov dx, [si]
    call newpos
    jz .nodirchange
    mov [si + 2], al
.nodirchange:
    mov al, [si + 2]
    mov dx, [si]
    call newpos   
    jz .endbootman
.move:
    mov ax, 0x0f20
    cmp byte [es:di], 0x04       ; Detect power pill
    jnz .nopowerpill
    mov byte [si + timer_offset], al
.nopowerpill:
    xchg dx, [si]
    call paint
.endbootman:

    ; ghost AI
    mov bx, 3 * gh_length + bm_length
    mov byte [si + collision_offset], bh    ; bh = 0 at this point
.ghost_ai_outer:
    mov bp, 0xffff          ; bp = minimum distance; start out at maxint
    mov al, 0xce
    mov ah, [bx + si]       ; ah contains the forbidden direction. The forbidden dir is backwards, unless 
                            ; boot-man just picked up a powerpill, in which case the current dir is forbidden
    cmp byte [si + timer_offset], 0x20
    jz .reverse
    xor ah, 8               ; Flip the current direction to obtain the forbidden one
.reverse:
    mov dx, [bx + si + gh_offset_pos]
    cmp dx, [si]            ; collision detection
    jne .ghost_ai_loop
    mov [si + collision_offset], al
.ghost_ai_loop:
    push dx
    cmp al, ah
    jz .next
    call newpos
    jz .next
    mov cx, 0x0c10
    cmp byte [si + timer_offset], bh        ; bh = 0 throughout this loop
    jnz .skip_target
    mov cx, [si]            ; Target postion for AI
    add cx, [bx + si + gh_offset_focus]
.skip_target:
    ; Calculate distance between new position and boot-man
    push ax
    sub cl, dl              ; Calculate delta_x
    sub ch, dh              ; Calculate delta_y

    movsx ax, cl
    imul ax, ax             ; ax = delta_x^2
    movsx cx, ch       
    imul cx, cx             ; cx = delta_y^2

    add cx, ax              ; cx = distance between positions in cx and dx
    pop ax

    ; Find out if distance is less than current minimum distance
    cmp cx, bp
    jnc .next
    mov bp, cx              ; new distance is less than distance found up to now
    mov [bx + si], al       ; hence, we choose this direction to move, for now
    mov [bx + si + gh_offset_pos], dx   ; Store the provisional new position
.next:
    pop dx
    sub al, 4
    cmp al, 0xc2
    jnc .ghost_ai_loop

    mov ax, [bx + si + gh_offset_terrain]   ; paint the terrain underneath the ghost at the old ghost position
    call paint

    sub bx, gh_length
    jns .ghost_ai_outer

    ; store terrain underneath ghosts
.ghostterrain_loop:
    mov dx, [bx + si + gh_offset_pos + gh_length]
    cmp dx, [si]            ; Collision detect after ghost movement
    jne .skip_collision
    mov [si + collision_offset], al

.skip_collision:
    call get_screenpos
    mov ax, [es:di]
    mov [bx + si + gh_offset_terrain + gh_length], ax
    add bx, gh_length
    cmp bx, 3 * gh_length + bm_length
    jnz .ghostterrain_loop

    ; Test if ghosts are invisible
    mov ax, 0x2fec
    mov cx, 0x0010
    cmp byte [si + timer_offset], ch
    jnz .ghosts_invisible

    ; Ghosts are visible, so test for collisions
    cmp byte [si + collision_offset], ch
    jz .no_collision

    ; Ghosts are visible and collide with boot-man, therefore boot-man is dead
    mov dx, [si]
    mov ax, 0x0e0f          ; Dead boot-man (yellow 8 pointed star)
    call paint
.halt:
    add byte [si + pace_offset], bl
    mov byte [jump_size], 2
    jmp intxhandler_end

    ; Ghosts are invisible
.ghosts_invisible:
    dec byte [si + timer_offset]
    mov ah, 0x0f
    mov cl, 0x0

.no_collision:
    ; Draw the ghosts on the screen
.ghostdraw:
    mov dx, [bx + si + gh_offset_pos]
    call paint
    add ah, cl            ; Update ghost colour
    sub bx, gh_length
    jns .ghostdraw

    ; Draw boot-man on the screen
    mov ax, word 0x0e02
    mov dx, [si]
    call paint

.end:
    jmp intxhandler_end


newpos:
    mov [.modified_instruction + 1], al
.modified_instruction:
    db 0xfe, 0xc2   ; inc dl in machine code
                    ; The last byte of this gets overwritten with the value of al before execution.
                    ; Valid values of al are: 0xc2 (inc dl), 0xc6 (inc dh), 0xca (dec dl), 0xce (dec dh).
                    ; These values correspond to moving right, down, left and up, respectively.
    and dl, 0x1f    ; Deal with tunnels
get_screenpos:
    push dx
    movzx di, dh
    imul di, di, 0x28
    mov dh, 0
    add di, dx
    shl di, 1
    add di, 8
    pop dx
    cmp byte [es:di], 0xdb
    ret


paint:
    call get_screenpos
    stosw
    ret


int9handler:
    pusha
    in al, 0x60

    ; This code converts al from scancode to movement direction.
    ; Input:  0x11 (W),  0x1e (A),     0x1f (S),    0x20 (D)
    ; Output: 0xce (up), 0xca (right), 0xc6 (down), 0xc2 (left) 
    ;
    ; Other scancodes below 0x21 are also mapped onto a movement direction
    ; Starting input:             0x11 0x1e 0x1f 0x20
    sub al, 0x21                ; 0xf0 0xfd 0xfe 0xff
    jnc intxhandler_end         ;                      if al >= 0x21, ignore scancode
    and al, 3                   ; 0x00 0x01 0x02 0x03
    shl al, 2                   ; 0x00 0x04 0x08 0x0c
    neg al                      ; 0x00 0xfc 0xf8 0xf4
    add al, 0xce                ; 0xce 0xca 0xc6 0xc2
    cmp al, [bootman_data + 2]
    jz intxhandler_end
    mov [bootman_data + 3], al
intxhandler_end:
    popa
    iret

bootman_data:
    db 0x0f, 0x0f   ; boot-man's x and y position
    db 0xca         ; boot-man's direction
    db 0xca         ; boot-man's future direction

pace_counter: db 0x10
ghost_timer: db 0x0 ; if > 0 ghosts are invisible, and is counted backwards to 0

ghostdata:
    db 0xc2        ; 1st ghost, direction
ghostpos:
    db 0x01, 0x01  ;            x and y position
ghostterrain:
    dw 0x0ff9      ;            terrain underneath
ghostfocus:
    db 0x0, 0x0    ;            focus point for movement
secondghost:
    db 0xce        ; 2nd ghost, direction
    db 0x01, 0x17  ;            x and y position
    dw 0x0ff9      ;            terrain underneath
    db 0x0, 0x4
    db 0xca        ; 3rd ghost, direction
    db 0x1e, 0x01  ;            x and y position
    dw 0x0ff9      ;            terrain underneath
    db 0xfc, 0x0
    db 0xce        ; 4th ghost, direction
    db 0x1e, 0x17  ;            x and y position
    dw 0x0ff9      ;            terrain underneath
    db 0x4, 0x0
lastghost:

bm_length           equ ghostdata - bootman_data
gh_length           equ secondghost  - ghostdata
gh_offset_pos       equ ghostpos     - ghostdata
gh_offset_terrain   equ ghostterrain - ghostdata
gh_offset_focus     equ ghostfocus   - ghostdata
pace_offset         equ pace_counter - bootman_data
timer_offset        equ ghost_timer - bootman_data

maze: dw 0xffff, 0x8000, 0xbffd, 0x8081, 0xfabf, 0x8200, 0xbefd, 0x8001
      dw 0xfebf, 0x0080, 0xfebf, 0x803f, 0xaebf, 0xaebf, 0x80bf, 0xfebf
      dw 0x0080, 0xfefd, 0x8081, 0xbebf, 0x8000, 0xbefd, 0xbefd, 0x8001
      dw 0xffff
maze_length: equ $ - maze

collision_detect:

collision_offset equ collision_detect - bootman_data

times 510 - ($ - $$) db 0
db 0x55
db 0xaa