TITLE Temperature File Reversal Program         (Proj6_bairsamu.asm)

; Author: Samuel Baird
; Last Modified: 03/15/2026
; OSU email address: bairsamu@oregonstate.edu
; Course number/section:   CS271 Section 400
; Project Number: 6                Due Date: 03/15/2026
; Description: Reads a comma-delimited file of ASCII temperature integers,
;              parses each line into an SDWORD array, and prints each line
;              reversed. Uses LODSB/STOSB for string handling. All params
;              passed on the stack via STDCALL.
;
; **EC1: Handles multi-line files -- each line reversed and printed separately,
;        labeled "Corrected Input Line N:".
; **EC2: WriteVal procedure converts integers to ASCII strings with STOSB and
;        displays them via mDisplayString instead of WriteInt/WriteDec.

INCLUDE Irvine32.inc

; -----------------------------------------------------------------------
; constants
; -----------------------------------------------------------------------
TEMPS_PER_DAY   =   24          ; temps per line, tested 1-48
DELIMITER       =   ','         ; separates values in the file
CR              =   13
LF              =   10
MAX_BUF         =   8192        ; file buffer size
MAX_FNAME       =   256
VALBUF          =   22          ; fits "-2147483648" + null terminator

; -----------------------------------------------------------------------
; macros
; -----------------------------------------------------------------------

; ---------------------------------------------------------
; mGetString
; Displays a prompt then reads keyboard input into a buffer.
; Receives: prompt (input, ref), buf (output, ref),
;           bufSize (input, val), numBytes (output, ref)
; ---------------------------------------------------------
mGetString  MACRO   prompt, buf, bufSize, numBytes
    PUSH    EAX
    PUSH    ECX
    PUSH    EDX
    mDisplayString  prompt
    MOV     EDX, buf
    MOV     ECX, bufSize
    CALL    ReadString          ; EAX = bytes read
    MOV     EDX, numBytes
    MOV     [EDX], EAX
    POP     EDX
    POP     ECX
    POP     EAX
ENDM

; ---------------------------------------------------------
; mDisplayString
; Prints null-terminated string at given address.
; Receives: strAddr (input, ref)
; ---------------------------------------------------------
mDisplayString  MACRO   strAddr
    PUSH    EDX
    MOV     EDX, strAddr
    CALL    WriteString
    POP     EDX
ENDM

; ---------------------------------------------------------
; mDisplayChar
; Prints a single ASCII character (immediate or constant).
; Receives: ch (input, immediate/constant)
; ---------------------------------------------------------
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

ec1str      BYTE    "**EC: This program reads multi-line input files and reverses "
            BYTE    "each line independently.", 0

ec2str      BYTE    "**EC: This program implements a WriteVal procedure to convert "
            BYTE    "integers to strings and display them, rather than using "
            BYTE    "WriteDec/WriteInt.", 0

prompt1     BYTE    "Enter the name of the file to be read: ", 0
hdrMsg      BYTE    "Here's the corrected temperature order!", 0
lineHdr     BYTE    "Corrected Input Line ", 0
errMsg      BYTE    "Error: could not open file.", 0
goodbyeMsg  BYTE    CR, LF, "Hope that helps resolve the issue, goodbye!", 0

; runtime buffers
fname       BYTE    MAX_FNAME   DUP(0)
fnLen       DWORD   0
fileBuf     BYTE    MAX_BUF     DUP(0)
temps       SDWORD  TEMPS_PER_DAY DUP(0)

; -----------------------------------------------------------------------
.code
; -----------------------------------------------------------------------


; -----------------------------------------------------------------------
; ParseTempsFromString
; Description: Parses TEMPS_PER_DAY signed integers from one line of the
;              file buffer and stores them in the temps array. Uses LODSB
;              to walk through the string character by character.
;
; Receives: [EBP+12] address of current line in fileBuf (input, ref)
;           [EBP+8]  address of temps array (output, ref)
; Returns:  EAX = pointer to start of next line in buffer
; Preconditions: line is CR/LF or null terminated
; Registers changed: EAX (return val); EBX ECX EDX ESI EDI saved/restored
; -----------------------------------------------------------------------
ParseTempsFromString    PROC

    PUSH    EBP
    MOV     EBP, ESP
    PUSH    EBX
    PUSH    ECX
    PUSH    EDX
    PUSH    ESI
    PUSH    EDI

    MOV     ESI, [EBP+12]       ; start of current line
    MOV     EDI, [EBP+8]        ; temps array
    MOV     ECX, TEMPS_PER_DAY

nextTemp:
    ; figure out sign first
    MOV     EDX, 1
    LODSB
    CMP     AL, '-'
    JNE     chkPlus
    MOV     EDX, -1
    LODSB                       ; move past the minus sign
    JMP     accumulate

chkPlus:
    CMP     AL, '+'
    JNE     accumulate          ; no sign char, AL is already first digit
    LODSB

accumulate:
    MOV     EBX, 0

digitLoop:
    CMP     AL, DELIMITER
    JE      storeVal
    CMP     AL, CR
    JE      lineEnd
    CMP     AL, LF
    JE      lineEnd
    CMP     AL, 0
    JE      nullEnd

    ; convert digit and fold into accumulator
    SUB     AL, '0'
    MOVZX   EAX, AL
    IMUL    EBX, EBX, 10
    ADD     EBX, EAX
    LODSB
    JMP     digitLoop

storeVal:
    ; hit the delimiter -- store and loop
    IMUL    EBX, EDX
    MOV     [EDI], EBX
    ADD     EDI, 4
    LOOP    nextTemp
    JMP     parseEnd

lineEnd:
    ; end of line -- store last value and consume the LF
    IMUL    EBX, EDX
    MOV     [EDI], EBX
    CMP     AL, CR
    JNE     parseEnd            ; was just a LF, ESI already past it
    LODSB                       ; eat the LF after CR
    CMP     AL, LF
    JE      parseEnd
    DEC     ESI                 ; not a LF, back up
    JMP     parseEnd

nullEnd:
    ; hit end of file
    IMUL    EBX, EDX
    MOV     [EDI], EBX
    DEC     ESI                 ; keep ESI on the null so caller stops

parseEnd:
    MOV     EAX, ESI

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
; Description: Converts a signed integer to an ASCII string and prints it
;              using mDisplayString. Uses STOSB to build the string in a
;              local buffer. Positive values get a '+' prefix.
;
; Receives: [EBP+8] SDWORD value to print (input, by value)
; Returns:  nothing
; Preconditions: none
; Registers changed: none (EAX EBX ECX EDX EDI saved/restored)
; -----------------------------------------------------------------------
WriteVal    PROC

    PUSH    EBP
    MOV     EBP, ESP
    SUB     ESP, VALBUF         ; local string buffer

    PUSH    EAX
    PUSH    EBX
    PUSH    ECX
    PUSH    EDX
    PUSH    EDI

    LEA     EDI, [EBP - VALBUF]

    MOV     EAX, [EBP+8]
    MOV     ECX, 0

    ; write sign character
    CMP     EAX, 0
    JGE     positiveVal
    MOV     BYTE PTR [EDI], '-'
    INC     EDI
    NEG     EAX
    JMP     pushDigits
positiveVal:
    MOV     BYTE PTR [EDI], '+'
    INC     EDI

pushDigits:
    ; push digits onto stack so we can pop them in the right order
divLoop:
    MOV     EDX, 0
    MOV     EBX, 10
    DIV     EBX                 ; remainder in EDX is next digit
    PUSH    EDX
    INC     ECX
    CMP     EAX, 0
    JNZ     divLoop

popDigits:
    POP     EDX
    ADD     DL, '0'
    MOV     AL, DL
    STOSB
    DEC     ECX
    JNZ     popDigits

    ; null terminate and display
    MOV     AL, 0
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
; Description: Prints the temps array in reverse order with DELIMITER
;              between values. Uses register indirect (SUB ESI, 4) to
;              walk backwards. Calls WriteVal for each integer (EC2) and
;              mDisplayChar for the delimiter.
;
; Receives: [EBP+8] address of temps array (input, ref)
; Returns:  nothing
; Preconditions: temps array has TEMPS_PER_DAY valid SDWORDs
; Registers changed: none (EAX ECX ESI saved/restored)
; -----------------------------------------------------------------------
WriteTempsReverse   PROC

    PUSH    EBP
    MOV     EBP, ESP
    PUSH    EAX
    PUSH    ECX
    PUSH    ESI

    MOV     ESI, [EBP+8]
    MOV     ECX, TEMPS_PER_DAY

    ; move ESI to last element
    MOV     EAX, TEMPS_PER_DAY
    DEC     EAX
    IMUL    EAX, EAX, 4
    ADD     ESI, EAX

revLoop:
    MOV     EAX, [ESI]
    PUSH    EAX
    CALL    WriteVal
    mDisplayChar    DELIMITER
    SUB     ESI, 4              ; step back one SDWORD
    LOOP    revLoop

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

    ; print intro and EC announcements
    mDisplayString  OFFSET intro
    CALL    CrLf
    mDisplayString  OFFSET ec1str
    CALL    CrLf
    mDisplayString  OFFSET ec2str
    CALL    CrLf
    CALL    CrLf

    ; get the filename from the user
    mGetString  OFFSET prompt1, OFFSET fname, MAX_FNAME, OFFSET fnLen
    CALL    CrLf

    ; try to open the file
    MOV     EDX, OFFSET fname
    CALL    OpenInputFile
    CMP     EAX, INVALID_HANDLE_VALUE
    JNE     fileOk
    mDisplayString  OFFSET errMsg
    CALL    CrLf
    JMP     quit

fileOk:
    MOV     EBX, EAX            ; hang onto the file handle

    ; read contents into fileBuf
    MOV     EDX, OFFSET fileBuf
    MOV     ECX, MAX_BUF - 1
    CALL    ReadFromFile
    MOV     fileBuf[EAX], 0     ; null terminate whatever we read

    MOV     EAX, EBX
    CALL    CloseFile

    ; print the header
    mDisplayString  OFFSET hdrMsg
    CALL    CrLf

    ; walk through each line of the file (EC1)
    MOV     ESI, OFFSET fileBuf
    MOV     ECX, 0              ; line number counter

nextLine:
    ; stop at null terminator
    CMP     BYTE PTR [ESI], 0
    JE      allDone

    ; skip any stray CR or LF bytes
    CMP     BYTE PTR [ESI], CR
    JE      skipOne
    CMP     BYTE PTR [ESI], LF
    JE      skipOne

    ; new line -- increment counter and print label
    INC     ECX
    PUSH    ECX
    mDisplayString  OFFSET lineHdr
    PUSH    ECX
    CALL    WriteVal            ; print the line number
    MOV     AL, ':'
    CALL    WriteChar
    CALL    CrLf
    POP     ECX

    ; parse and reverse this line
    PUSH    ESI
    PUSH    OFFSET temps
    CALL    ParseTempsFromString
    MOV     ESI, EAX            ; EAX has pointer to next line

    PUSH    OFFSET temps
    CALL    WriteTempsReverse
    CALL    CrLf

    JMP     nextLine

skipOne:
    INC     ESI
    JMP     nextLine

allDone:
    mDisplayString  OFFSET goodbyeMsg
    CALL    CrLf

quit:
    INVOKE  ExitProcess, 0

main    ENDP

END main
