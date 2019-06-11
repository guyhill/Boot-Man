org 0x7c00
bits 16

start:
    cli
    xor ax, ax          
    mov ds, ax
    mov [bootdrive], dl ; save the current drive number, which has been stored in dl by the BIOS
    mov ss, ax          
    mov sp, 0x28        ; Set up temporary stack within the interrupt vector table
    push ax             ; This saves some bytes when setting up interrupt vectors
    push word int9handler   
    push ax
    push word int8handler
    
    mov sp, ax          ; Set up the real stack. This is safe to do as interrupts have been disabled

    inc ax              ; Go to 40x25 character video mode
    int 0x10            

    mov cx, 0x2000      ; Remove cursor from screen
    mov ah, 0x01
    int 0x10


    cld
    mov ax, 0xb800
    mov es, ax          ; es points to video RAM

buildmaze:
    mov di, 0x0788                  ; Lower left corner of maze in video ram
    mov si, maze
    mov dx, 0x05fa                  ; Address in video ram of lower left powerpill
.maze_outerloop:
    mov cx, 0x003c
    lodsw
.maze_innerloop:
    shl ax, 1
    push ax
    mov ax, 0x01db                  ; wall character (blue solid square)
    jc .draw
    mov ax, 0x0ff9                  ; food character (white dot)
    cmp di, dx
    jnz .draw
    mov dh, 0x00                    ; Update powerpill address to draw remaining powerpills
    mov al, 0x04                    ; powerpill character (white diamond)
.draw:
    stosw
    push di
    add di, cx
    stosw
    pop di
    pop ax
    sub cx, 4
    jns .maze_innerloop

    sub di, 0x70
    jns .maze_outerloop

    sti
.end:
    mov al, 0x20
    out 0x20, al
    jmp .end


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