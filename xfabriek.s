
; Xfabriek - started 2022-02-18
; by MooingLemur

; Music tracker for the Commander X16

; Let's start with something simple

; This is for the 65C02.  This assembler directive enables
; the use of 65C02-specific mnemonics.
; (PHX/PLX, PHY/PLY, BRA, ...)
.PC02


; Add the PRG header
.segment "HEADER"
.word $0801

.segment "CODE"
; Add a BASIC startline
.word entry-2
.byte $00,$00,$9e
.byte "2061"
.byte $00,$00,$00

; Entry point at $080d
entry:
    jmp main

.pushseg
.segment "ZEROPAGE"
xf_tmp1: .res 1
xf_tmp2: .res 1
xf_tmp3: .res 1
.popseg


.include "x16.inc"
.include "vars.s"
.include "customchars.s"
.include "grid.s"
.include "sequencer.s"
.include "instruments.s"
.include "undo.s"
.include "clipboard.s"
.include "function.s"
.include "util.s"
.include "irq.s"
.include "keyboard.s"



XF_BASE_BG_COLOR = $00 ; black
XF_AUDITION_BG_COLOR = $60 ; blue
XF_NOTE_ENTRY_BG_COLOR = $20 ; red
XF_CURSOR_BG_COLOR = $F0 ; light grey
XF_HILIGHT_BG_COLOR_1 = $B0 ; dark grey
XF_HILIGHT_BG_COLOR_2 = $C0 ; grey
XF_SELECTION_BG_COLOR = $50 ; green

XF_BASE_FG_COLOR = $01 ; white
XF_INST_FG_COLOR = $0D ; green
XF_VOL_FG_COLOR = $03 ; cyan
XF_EFFECT_FG_COLOR = $0E ; light blue

.segment "CODE"

redraw: .res 1 ; flag on when a redraw is necessary
xf_state: .res 1

XF_STATE_DUMP = 0 ; we end up here when we need to dump memory state to SD
XF_STATE_NEW_DIALOG = 1
XF_STATE_SAVE_DIALOG = 2
XF_STATE_LOAD_DIALOG = 3
XF_STATE_GRID = 4
;XF_STATE_PATTERN_EDITOR_ENTRY = 5
XF_STATE_SEQUENCER = 6
XF_STATE_INSTRUMENT_PSG = 7
XF_STATE_INSTRUMENT_FM = 8
XF_STATE_INSTRUMENT_PCM = 9
XF_STATE_PLAYBACK = 10

main:
    jsr xf_set_charset

    jsr xf_clear_screen

    jsr CustomChars::install

    lda #XF_STATE_GRID
    sta xf_state

    lda #64
    sta Grid::global_pattern_length

    lda #16
    sta Grid::long_hilight_interval
    lda #4
    sta Grid::short_hilight_interval

    jsr xf_irq::setup

    jsr Keyboard::setup_handler

    sec
    jsr x16::Kernal::SCREEN_MODE ; get current screen size (in 8px) into .X and .Y
    lda #1
    jsr x16::Kernal::MOUSE_CONFIG ; show the default mouse pointer

    lda #1
    sta Sequencer::base_bank

    lda #2
    sta Instruments::base_bank

    lda #6
    sta Undo::base_bank

    lda #$0A
    sta Clipboard::base_bank

    lda #$10
    sta Grid::base_bank

    lda #3
    sta Sequencer::max_frame

    lda #47
    sta Sequencer::max_pattern

    inc redraw

    lda #1
    sta Grid::step

    lda #$00
    sta Undo::lookup_addr
    lda #$A0
    sta Undo::lookup_addr+1




    ; TODO detect emulator and report if the toggle failed

    ; toggle emulator keys off
    lda #1
    sta $9FB7



@mainloop:

    lda redraw
    beq :+
        stz redraw
        jsr Sequencer::draw
        jsr Instruments::draw
        jsr Grid::draw
    :
    wai

    ; if we have a pending note entry to do
    lda Function::op_dispatch_flag
    cmp #Function::OP_NOTE
    bne :+
        ; clear selection too
        stz Grid::selection_active

        stz Function::op_dispatch_flag
        lda Function::op_dispatch_operand
        stz Function::op_dispatch_operand
        jsr Function::note_entry
    :

    lda Function::op_dispatch_flag
    cmp #Function::OP_UNDO
    bne :+
        stz Function::op_dispatch_flag
        jsr Undo::undo
    :

    lda Function::op_dispatch_flag
    cmp #Function::OP_REDO
    bne :+
        stz Function::op_dispatch_flag
        jsr Undo::redo
    :

    lda Function::op_dispatch_flag
    cmp #Function::OP_BACKSPACE
    bne :+
        ; clear selection too
        stz Grid::selection_active

        stz Function::op_dispatch_flag
        jsr Function::delete_cell_above
    :

    lda Function::op_dispatch_flag
    cmp #Function::OP_INSERT
    bne :+
        ; clear selection too
        stz Grid::selection_active

        stz Function::op_dispatch_flag
        jsr Function::insert_cell
    :

    lda Function::op_dispatch_flag
    cmp #Function::OP_COPY
    bne :+
        stz Function::op_dispatch_flag
        jsr Function::copy

    :

    lda Function::op_dispatch_flag
    cmp #Function::OP_DELETE
    bne :+
        stz Function::op_dispatch_flag
        jsr Function::delete_selection

    :

    lda Function::op_dispatch_flag
    cmp #Function::OP_CUT
    bne :+
        stz Function::op_dispatch_flag
        jsr Function::copy
        jsr Function::delete_selection
    :

    lda Function::op_dispatch_flag
    cmp #Function::OP_PASTE
    bne :+
        stz Function::op_dispatch_flag
        lda Function::op_dispatch_operand
        stz Function::op_dispatch_operand
        jsr Clipboard::paste_cells
    :

    lda Function::op_dispatch_flag
    cmp #Function::OP_DEC_SEQ_CELL
    bne :+
        stz Function::op_dispatch_flag
        jsr Function::decrement_sequencer_cell
    :

    lda Function::op_dispatch_flag
    cmp #Function::OP_INC_SEQ_CELL
    bne :+
        stz Function::op_dispatch_flag
        jsr Function::increment_sequencer_cell
    :


    VERA_SET_ADDR ($0010+$1B000),2
    lda Grid::cursor_position
    jsr xf_byte_to_hex
    sta Vera::Reg::Data0
    stx Vera::Reg::Data0

    lda Grid::x_position
    jsr xf_byte_to_hex
    sta Vera::Reg::Data0
    stx Vera::Reg::Data0

    lda Keyboard::scancode
    jsr xf_byte_to_hex
    sta Vera::Reg::Data0
    stx Vera::Reg::Data0

    lda Keyboard::scancode+1
    jsr xf_byte_to_hex
    sta Vera::Reg::Data0
    stx Vera::Reg::Data0

    lda Keyboard::modkeys
    jsr xf_byte_to_hex
    sta Vera::Reg::Data0
    stx Vera::Reg::Data0

    lda #' '
    sta Vera::Reg::Data0
    lda Grid::selection_top_y
    jsr xf_byte_to_hex
    sta Vera::Reg::Data0
    stx Vera::Reg::Data0

    lda #' '
    sta Vera::Reg::Data0
    lda Grid::selection_bottom_y
    jsr xf_byte_to_hex
    sta Vera::Reg::Data0
    stx Vera::Reg::Data0

    lda #' '
    sta Vera::Reg::Data0
    lda Undo::undo_size+1
    jsr xf_byte_to_hex
    sta Vera::Reg::Data0
    stx Vera::Reg::Data0
    lda Undo::undo_size
    jsr xf_byte_to_hex
    sta Vera::Reg::Data0
    stx Vera::Reg::Data0


    lda #' '
    sta Vera::Reg::Data0
    lda Undo::redo_size+1
    jsr xf_byte_to_hex
    sta Vera::Reg::Data0
    stx Vera::Reg::Data0
    lda Undo::redo_size
    jsr xf_byte_to_hex
    sta Vera::Reg::Data0
    stx Vera::Reg::Data0


    lda #' '
    sta Vera::Reg::Data0
    lda Undo::current_bank_offset
    jsr xf_byte_to_hex
    sta Vera::Reg::Data0
    stx Vera::Reg::Data0
    lda Undo::lookup_addr+1
    jsr xf_byte_to_hex
    sta Vera::Reg::Data0
    stx Vera::Reg::Data0
    lda Undo::lookup_addr
    jsr xf_byte_to_hex
    sta Vera::Reg::Data0
    stx Vera::Reg::Data0


    jmp @mainloop
@exit:
;	DO THIS WHEN WE'RE EXITING FOR REAL
    jsr xf_irq::teardown
    jsr xf_reset_charset
    rts
