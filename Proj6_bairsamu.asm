TITLE Temperature File Reversal Program         (Proj6_bairsamu.asm)

; Author: Samuel Baird
; Last Modified: 03/15/2026
; OSU email address: bairsamu@oregonstate.edu
; Course number/section:   CS271 Section 400
; Project Number: 6                Due Date: 03/15/2026
; Description: Reads a comma-delimited file of temperature values (ASCII integers),
;              parses each line into an array of SDWORDs, then prints each line
;              back out in reverse order. Uses LODSB/STOSB for string handling.
;              Parameters are passed on the stack (STDCALL).
;
; **EC1: Program handles multi-line files -- each line gets reversed and printed
;        separately with a "Corrected Input Line N:" label.
; **EC2: Wrote a WriteVal procedure that converts an integer to a string using
;        STOSB and prints it with mDisplayString instead of using WriteInt.

INCLUDE Irvine32.inc

; -----------------------------------------------------------------------
; constants
; -----------------------------------------------------------------------
TEMPS_PER_DAY   =   24
DELIMITER       =   ','
CR              =   13
LF              =   10
MAX_BUF         =   8192
MAX_FNAME       =   256
VALBUF          =   22          ; big enough for -2147483648 plus null

; -----------------------------------------------------------------------
; macros
; -----------------------------------------------------------------------

; mGetString: show prompt, read input into buffer
; params: prompt addr, buffer addr, buffer size, addr to store byte count
mGetString  MACRO   prompt, buf, bufSize, numBytes
    PUSH    EAX
    PUSH    ECX
    PUSH    EDX
    mDisplayString  prompt
    MOV     EDX, buf
    MOV     ECX, bufSize
    CALL    ReadString
    MOV     EDX, numBytes
    MOV     [EDX], EAX
    POP     EDX
    POP     ECX
    POP     EAX
ENDM

; mDisplayString: print a string given its address
mDisplayString  MACRO   strAddr
    PUSH    EDX
    MOV     EDX, strAddr
    CALL    WriteString
    POP     EDX
ENDM

; mDisplayChar: print a single character (immediate or constant)
mDisplayChar    MACRO   ch
    PUSH    EAX
    MOV     AL, ch
    CALL    WriteChar
    POP     EAX
ENDM

; -----------------------------------------------------------------------
.data
; -----------------------------------------------------------------------

intro       BYTE    "Welcome to the intern error-corrector! I'll read a "
            BYTE    "','-delimited file storing a series of temperature values.", CR, LF
            BYTE    "The file must be ASCII-formatted. I'll then reverse the ordering "
            BYTE    "and provide the corrected temperature", CR, LF
            BYTE    "ordering as a printout!", 0

ec1str      BYTE    "**EC: This program reads multi-line files and reverses each line "
            BYTE    "independently.", 0

ec2str      BYTE    "**EC: This program implements a WriteVal procedure to convert "
            BYTE    "integers to strings and display them, rather than using "
            BYTE    "WriteDec/WriteInt.", 0

prompt1     BYTE    "Enter the name of the file to be read: ", 0
hdr         BYTE    "Here's the corrected temperature order!", 0
lineHdr     BYTE    "Corrected Input Line ", 0
errMsg      BYTE    "Error opening file. Exiting.", 0
bye         BYTE    CR, LF, "Hope that helps resolve the issue, goodbye!", 0

; buffers
fname       BYTE    MAX_FNAME   DUP(0)
fnLen       DWORD   0
fileBuf     BYTE    MAX_BUF     DUP(0)
temps       SDWORD  TEMPS_PER_DAY DUP(0)

; -----------------------------------------------------------------------
.code
; -----------------------------------------------------------------------


; -----------------------------------------------------------------------
; ParseTempsFromString
; reads TEMPS_PER_DAY integers out of one line of the file buffer,
; stores them in the temps array as SDWORDs.
; uses LODSB to walk through the string.
;
; params (stdcall):
;   [EBP+12]  ptr to start of current line in fileBuf  (input, ref)
;   [EBP+8]   ptr to temps array                       (output, ref)
;
; returns EAX = pointer to start of next line
; -----------------------------------------------------------------------
ParseTempsFromString    PROC

    PUSH    EBP
    MOV     EBP, ESP
    PUSH    EBX
    PUSH    ECX
    PUSH    EDX
    PUSH    ESI
    PUSH    EDI

    MOV     ESI, [EBP+12]       ; source -- current line
    MOV     EDI, [EBP+8]        ; destination -- temps array
    MOV     ECX, TEMPS_PER_DAY

nextTemp:
    ; check sign
    MOV     EDX, 1
    LODSB
    CMP     AL, '-'
    JNE     chkPlus
    MOV     EDX, -1
    LODSB
    JMP     doDigits

chkPlus:
    CMP     AL, '+'
    JNE     doDigits
    LODSB                       ; skip the plus, grab first digit

doDigits:
    MOV     EBX, 0              ; accumulator

digitLoop:
    CMP     AL, DELIMITER
    JE      saveit
    CMP     AL, CR
    JE      endOfLine
    CMP     AL, LF
    JE      endOfLine
    CMP     AL, 0
    JE      hitNull

    ; it's a digit
    SUB     AL, '0'
    MOVZX   EAX, AL
    IMUL    EBX, EBX, 10
    ADD     EBX, EAX
    LODSB
    JMP     digitLoop

saveit:
    ; hit delimiter -- store and keep going
    IMUL    EBX, EDX
    MOV     [EDI], EBX
    ADD     EDI, 4
    LOOP    nextTemp
    JMP     alldone

endOfLine:
    ; hit CR -- store last value, eat the LF
    IMUL    EBX, EDX
    MOV     [EDI], EBX
    CMP     AL, CR
    JNE     alldone
    LODSB                       ; eat LF
    CMP     AL, LF
    JE      alldone
    DEC     ESI                 ; wasn't LF, back up
    JMP     alldone

hitNull:
    ; end of file mid-line
    IMUL    EBX, EDX
    MOV     [EDI], EBX
    DEC     ESI

alldone:
    MOV     EAX, ESI            ; return updated pointer

    POP     EDI
    POP     ESI
    POP     EDX
    POP     ECX
    POP     EBX
    POP     EBP
    RET     8

ParseTempsFromString    ENDP


; -----------------------------------------------------------------------
; WriteVal  (EC2)
; takes a signed integer by value, converts it to an ASCII string using
; STOSB, then displays it with mDisplayString. positive values get a +.
;
; param: [EBP+8]  SDWORD value (input, by value)
; -----------------------------------------------------------------------
WriteVal    PROC

    PUSH    EBP
    MOV     EBP, ESP
    SUB     ESP, VALBUF         ; local buffer for the string

    PUSH    EAX
    PUSH    EBX
    PUSH    ECX
    PUSH    EDX
    PUSH    EDI

    LEA     EDI, [EBP - VALBUF]

    MOV     EAX, [EBP+8]
    MOV     ECX, 0              ; digit count

    ; write sign
    CMP     EAX, 0
    JGE     isPos
    MOV     BYTE PTR [EDI], '-'
    INC     EDI
    NEG     EAX
    JMP     getDigits
isPos:
    MOV     BYTE PTR [EDI], '+'
    INC     EDI

getDigits:
    ; push digits onto stack then pop in order
wvDivLoop:
    MOV     EDX, 0
    MOV     EBX, 10
    DIV     EBX                 ; EAX = quotient, EDX = remainder
    PUSH    EDX
    INC     ECX
    CMP     EAX, 0
    JNZ     wvDivLoop

wvPopLoop:
    POP     EDX
    ADD     DL, '0'
    MOV     AL, DL
    STOSB
    DEC     ECX
    JNZ     wvPopLoop

    MOV     AL, 0               ; null terminate
    STOSB

    LEA     EDX, [EBP - VALBUF]
    mDisplayString  EDX

    POP     EDI
    POP     EDX
    POP     ECX
    POP     EBX
    POP     EAX
    MOV     ESP, EBP
    POP     EBP
    RET     4

WriteVal    ENDP


; -----------------------------------------------------------------------
; WriteTempsReverse
; prints temps array in reverse order, delimiter after each value.
; walks array backwards with register indirect (SUB ESI, 4).
; calls WriteVal for each integer (EC2), mDisplayChar for delimiter.
;
; param: [EBP+8]  address of temps array (input, ref)
; -----------------------------------------------------------------------
WriteTempsReverse   PROC

    PUSH    EBP
    MOV     EBP, ESP
    PUSH    EAX
    PUSH    ECX
    PUSH    ESI

    MOV     ESI, [EBP+8]
    MOV     ECX, TEMPS_PER_DAY

    ; point ESI at last element
    MOV     EAX, TEMPS_PER_DAY
    DEC     EAX
    IMUL    EAX, EAX, 4
    ADD     ESI, EAX

printLoop:
    MOV     EAX, [ESI]
    PUSH    EAX
    CALL    WriteVal
    mDisplayChar    DELIMITER
    SUB     ESI, 4
    LOOP    printLoop

    POP     ESI
    POP     ECX
    POP     EAX
    POP     EBP
    RET     4

WriteTempsReverse   ENDP


; -----------------------------------------------------------------------
; main
; -----------------------------------------------------------------------
main    PROC

    ; intro
    mDisplayString  OFFSET intro
    CALL    CrLf
    mDisplayString  OFFSET ec1str
    CALL    CrLf
    mDisplayString  OFFSET ec2str
    CALL    CrLf
    CALL    CrLf

    ; get filename
    mGetString  OFFSET prompt1, OFFSET fname, MAX_FNAME, OFFSET fnLen
    CALL    CrLf

    ; open file
    MOV     EDX, OFFSET fname
    CALL    OpenInputFile
    CMP     EAX, INVALID_HANDLE_VALUE
    JNE     opened
    mDisplayString  OFFSET errMsg
    CALL    CrLf
    JMP     done

opened:
    MOV     EBX, EAX            ; save handle

    ; read file
    MOV     EDX, OFFSET fileBuf
    MOV     ECX, MAX_BUF - 1
    CALL    ReadFromFile
    MOV     fileBuf[EAX], 0     ; null terminate

    ; close
    MOV     EAX, EBX
    CALL    CloseFile

    mDisplayString  OFFSET hdr
    CALL    CrLf

    ; loop through each line (EC1)
    MOV     ESI, OFFSET fileBuf
    MOV     ECX, 0              ; line counter

lineLoop:
    CMP     BYTE PTR [ESI], 0
    JE      finished

    ; skip stray CR/LF bytes
    CMP     BYTE PTR [ESI], CR
    JE      skipByte
    CMP     BYTE PTR [ESI], LF
    JE      skipByte

    INC     ECX

    ; print line label
    PUSH    ECX
    mDisplayString  OFFSET lineHdr
    PUSH    ECX
    CALL    WriteVal
    MOV     AL, ':'
    CALL    WriteChar
    CALL    CrLf
    POP     ECX

    ; parse the line
    PUSH    ESI
    PUSH    OFFSET temps
    CALL    ParseTempsFromString
    MOV     ESI, EAX            ; advance to next line

    ; print reversed
    PUSH    OFFSET temps
    CALL    WriteTempsReverse
    CALL    CrLf

    JMP     lineLoop

skipByte:
    INC     ESI
    JMP     lineLoop

finished:
    mDisplayString  OFFSET bye
    CALL    CrLf

done:
    INVOKE  ExitProcess, 0

main    ENDP

END main
