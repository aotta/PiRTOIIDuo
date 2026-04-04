	ROMW 16
intybasic_map:	equ 0	; ROM map used
intybasic_jlp:	equ 0	; JLP is used
intybasic_cc3:	equ 0	; CC3 is used and where is RAM
intybasic_ecs:	equ 0	; Forces to include ECS startup
intybasic_voice:	equ 0	; Forces to include voice library
intybasic_flash:	equ 0	; Forces to include Flash memory library
intybasic_scroll:	equ 0	; Forces to include scroll library
intybasic_col:	equ 0	; Forces to include collision detection
intybasic_keypad:	equ 0	; Forces to include keypad library
intybasic_music:	equ 0	; Forces to include music library
intybasic_music_ecs:	equ 0	; Forces to include music library
intybasic_music_volume:	equ 0	; Forces to include music volume change
intybasic_stack:	equ 0	; Forces to include stack overflow checking
intybasic_numbers:	equ 1	; Forces to include numbers library
intybasic_fastmult:	equ 0	; Forces to include fast multiplication
intybasic_fastdiv:	equ 0	; Forces to include fast division/remainder
	;
	; Prologue for IntyBASIC programs
	; by Oscar Toledo G.  http://nanochess.org/
	;
	; Revision: Jan/30/2014. Spacing adjustment and more comments.
	; Revision: Apr/01/2014. It now sets the starting screen pos. for PRINT
	; Revision: Aug/26/2014. Added PAL detection code.
	; Revision: Dec/12/2014. Added optimized constant multiplication routines.
	;                        by James Pujals.
	; Revision: Jan/25/2015. Added marker for automatic title replacement.
	;                        (option --title of IntyBASIC)
	; Revision: Aug/06/2015. Turns off ECS sound. Seed random generator using
	;                        trash in 16-bit RAM. Solved bugs and optimized
	;                        macro for constant multiplication.
	; Revision: Jan/12/2016. Solved bug in PAL detection.
	; Revision: May/03/2016. Changed in _mode_select initialization.
	; Revision: Jul/31/2016. Solved bug in multiplication by 126 and 127.
	; Revision: Sep/08/2016. Now CLRSCR initializes screen position for PRINT,
	;                        this solves bug when user programs goes directly
	;                        to PRINT.
	; Revision: Oct/21/2016. Accelerated MEMSET.
	; Revision: Jan/09/2018. Adjusted PAL/NTSC constant.
	; Revision: Feb/05/2018. Forces initialization of Intellivoice if included.
	;                        So VOICE INIT ceases to be dangerous.
	; Revision: Oct/30/2018. Redesigned PAL/NTSC detection using intvnut code,
	;                        also now compatible with Tutorvision. Reformatted.
	; Revision: Jan/10/2018. Added ECS detection.
	;

    LISTING "off"

;;==========================================================================;;
;; IntyBASIC SDK Library: romseg-bs.mac                                     ;;
;;--------------------------------------------------------------------------;;
;;  This macro library is used by the IntyBASIC SDK to manage ROM address   ;;
;;  segments and generate statistics on program ROM usage.  It is an        ;;
;;  extension of the "romseg.mac" macro library with added support for      ;;
;;  bank-switching.                                                         ;;
;;                                                                          ;;
;;  The library is based on a similar module created for the P-Machinery    ;;
;;  programming framework, which itself was based on the "CART.MAC" macro   ;;
;;  library originally created by Joe Zbiciak and distributed as part of    ;;
;;  the SDK-1600 development kit.                                           ;;
;;--------------------------------------------------------------------------;;
;;      The file is placed into the public domain by its author.            ;;
;;      All copyrights are hereby relinquished on the routines and data in  ;;
;;      this file.  -- James Pujals (DZ-Jay), 2024-2025                     ;;
;;==========================================================================;;

;; ======================================================================== ;;
;;  ROM MANAGEMENT STRUCTURES                                               ;;
;; ======================================================================== ;;

                ; Internal ROM information structure
_rom            STRUCT  0
@@null          QEQU    0
@@invalid       QEQU    -1

@@legacy        QEQU    0
@@static        QEQU    1
@@dynamic       QEQU    2

@@mapcnt        QEQU    9
@@pgsize        QEQU    4096

@@open          QSET    @@invalid
@@error         QSET    @@null

@@segcnt        QSET    0
@@segs          QSET    0
                ENDS

.ROM            STRUCT  0
@@CurrentSeg    QSET    _rom.invalid    ; No open segment

@@Size          QSET    0
@@Used          QSET    0
@@Available     QSET    0

                ; Initialize segment counters
@@Segments[_rom.legacy ]    QSET    0
@@Segments[_rom.static ]    QSET    0
@@Segments[_rom.dynamic]    QSET    0

                ENDS

_rom_stat       STRUCT  0
@@space         QEQU    "                                                                           " ; 75
@@single        QEQU    "---------------------------------------------------------------------------"
@@double        QEQU    "==========================================================================="
                ENDS


;; ======================================================================== ;;
;;  __rom_raise_error(err, desc)                                            ;;
;;  Generates an assembler error and sets the global error flag.            ;;
;;                                                                          ;;
;;  NOTE:   Both strings must be devoid of semi-colons and commas, or       ;;
;;          Bad Things(tm) may happen during pre-processing.                ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      err         The error message.                                      ;;
;;      desc        Optional error description, or _rom.null if none.       ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 (failed).                                            ;;
;; ======================================================================== ;;
MACRO   __rom_raise_error(err, desc)
;
    LISTING "off"

_rom.error      QSET    _rom.invalid

_rom.err_len    QSET    _rom.null
_rom.err_len    QSET    %desc%

        IF (_rom.err_len <> _rom.null)
            ERR  $(%err%, ": ", %desc%)
        ELSE
            ERR  $(%err%)
        ENDI

    LISTING "prev"
ENDM

;; ======================================================================== ;;
;;  __rom_reset_error                                                       ;;
;;  Resets the global error flag.                                           ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      None.                                                               ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  0 (no error)                                            ;;
;; ======================================================================== ;;
MACRO   __rom_reset_error
;
_rom.error      QSET    _rom.null
ENDM

;; ======================================================================== ;;
;;  __rom_validate_map(map)                                                 ;;
;;  Validates the requested ROM map.                                        ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      map         The ROM map selected. Valid values are 0 to 7.          ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   __rom_validate_map(map)
;
_rom.max        QSET    (_rom.mapcnt - 1)

        IF (((%map%) < 0) OR ((%map%) > _rom.max))
            __rom_raise_error(["Invalid ROM map number (", $#(%map%), ")"], ["Valid maps are from 0 to ", $#(_rom.max), "."])
        ENDI
ENDM

;; ======================================================================== ;;
;;  __rom_validate_type(type)                                               ;;
;;  Validates the requested segment type symbol.                            ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      type        The segment type to validate.                           ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   __rom_validate_type(type)
;
        IF ((CLASSIFY(_rom.%type%) = -10000))
            __rom_raise_error("Invalid ROM segment type \"%type%\".", _rom.null)
        ENDI
ENDM

;; ======================================================================== ;;
;;  __rom_validate_segment(seg)                                             ;;
;;  Validates the requested segment number to ensure it is supported by the ;;
;;  active memory map.                                                      ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      seg         The segment number to validate.                         ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   __rom_validate_segment(seg)
;
        IF ((CLASSIFY(_rom.segidx[%seg%]) = -10000))
            __rom_raise_error(["Invalid ROM segment number #", $#(%seg%), " for selected memory map."], _rom.null)
        ENDI
ENDM

;; ======================================================================== ;;
;;  __rom_validate_seg_bank(seg, bank)                                      ;;
;;  Validates the requested dynamic segment and bank number to ensure it is ;;
;;  supported by the active memory map.                                     ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      seg         The segment number to validate, or -1 for the first one.;;
;;      bank        The dynamic segment bank number to validate.            ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   __rom_validate_seg_bank(seg, bank)
;
        ; First, check if the map supports dynamic segments at all
        IF (.ROM.Segments[_rom.dynamic] = 0)
                __rom_raise_error("The selected memory map does not support dynamic segments.", _rom.null)
        ENDI

        ; Validate the segment
        IF (_rom.error = _rom.null)
                __rom_validate_segment(%seg%)
        ENDI

        ; Validate the bank
        IF (_rom.error = _rom.null)

_rom.num    QSET    _rom.segidx[%seg%]
_rom.max    QSET    (_rom.bnkcnt[_rom.num] - 1)

            IF (((%bank%) < 0) OR ((%bank%) > _rom.max))
                __rom_raise_error(["Invalid bank number #", $#(%bank%), " for dynamic ROM segment #", $#(%seg%)], ["Must be between 0 and ", $#(_rom.max), "."])
            ENDI

        ENDI
ENDM

;; ======================================================================== ;;
;;  __rom_validate_segnum(segnum)                                           ;;
;;  Validates the requested internal segment number to ensure that it is    ;;
;;  valid within the active memory map.                                     ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      segnum      The internal memory map segment number to validate.     ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   __rom_validate_segnum(segnum)
;
        IF _EXPMAC ((CLASSIFY(_rom.t[%segnum%]) = -10000))
            __rom_raise_error(["Unknown internal ROM segment number #", $#(%segnum%), "."], _rom.null)
        ELSE

_rom.type   QSET    _rom.t[%segnum%]
_rom.max    QSET    (.ROM.Segments[_rom.type] - 1)

            IF _EXPMAC (((%segnum%) < 0) OR ((%segnum%) > _rom.max))
                __rom_raise_error(["Invalid internal segment number #", $#(%segnum%), " for selected memory map"], ["Must be a value between 0 and ", $#(_rom.max), "."])
            ENDI

        ENDI
ENDM

;; ======================================================================== ;;
;;  __rom_assert_setup(label)                                               ;;
;;  Ensures that ROM.Setup has been called.                                 ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      label       A quoted-string containing the label of the asserting   ;;
;;                  macro or function.                                      ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   __rom_assert_setup(label)
;
        IF ((CLASSIFY(_rom.init) = -10000))
            __rom_raise_error(["ROM", ".Setup directive must be used before calling ROM.", %label%, "."], _rom.null)
        ENDI
ENDM

;; ======================================================================== ;;
;;  __rom_assert_romseg_support(label)                                      ;;
;;  Prevents the invocation of a feature that is not supported by the       ;;
;;  legacy memory map when ROM map #0 is selected.                          ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      label       A quoted-string containing the label of the asserting   ;;
;;                  macro or function.                                      ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   __rom_assert_romseg_support(label)
;
        IF (_rom.map = 0)
            __rom_raise_error([%label%, " failed"], ["Legacy ROM map #", $#(_rom.map), " does not support it."])
        ENDI
ENDM

;; ======================================================================== ;;
;;  __rom_assert_def_order(type)                                            ;;
;;  Ensures that segments are defined in the proper order:  all legacy and  ;;
;;  static segments first, followed by all dynamic ones.                    ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      type        The segment type to check.                              ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   __rom_assert_def_order(type)
;
_rom.type   QSET    _rom.%type%

        ; Make sure all dynamic segments are defined last
        IF (((_rom.type = _rom.legacy) OR (_rom.type = _rom.static)) AND (.ROM.Segments[_rom.dynamic] > 0))
            __rom_raise_error("Invalid ROM segment definition order", "All static and legacy segments must be defined before any dynamic ones.")
        ENDI
ENDM

;; ======================================================================== ;;
;;  __rom_segmem_size(segnum)                                               ;;
;;  Computes the total size of a ROM segment.                               ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      segnum      The internal segment for which to compute the size.     ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      None.                                                               ;;
;; ======================================================================== ;;
MACRO   __rom_segmem_size(segnum)
;
.ROM.SegSize[%segnum%]  QSET (_rom.e[%segnum%] - _rom.b[%segnum%] + 1)
ENDM

;; ======================================================================== ;;
;;  __rom_segmem_used(segnum)                                               ;;
;;  Computes the usage of a ROM segment.                                    ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      segnum      The internal segment for which to compute the usage.    ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      None.                                                               ;;
;; ======================================================================== ;;
MACRO   __rom_segmem_used(segnum)
;
.ROM.SegUsed[%segnum%]  QSET (_rom.pos[%segnum%] - _rom.b[%segnum%])
ENDM

;; ======================================================================== ;;
;;  __rom_segmem_available(segnum)                                          ;;
;;  Computes the available space of a ROM segment.                          ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      segnum      The internal segment for which to compute the available ;;
;;                  space.                                                  ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      None.                                                               ;;
;; ======================================================================== ;;
MACRO   __rom_segmem_available(segnum)
;
.ROM.SegAvlb[%segnum%]  QSET (_rom.e[%segnum%] - _rom.pos[%segnum%] + 1)
ENDM

;; ======================================================================== ;;
;;  __rom_calculate_stats                                                   ;;
;;  Computes the total ROM size and usage statistics.                       ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      None.                                                               ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      None.                                                               ;;
;; ======================================================================== ;;
MACRO   __rom_calculate_stats
;
_rom.segnum     QSET    0

            REPEAT (_rom.segcnt)

.ROM.Size       SET     (.ROM.Size      + .ROM.SegSize[_rom.segnum])
.ROM.Used       SET     (.ROM.Used      + .ROM.SegUsed[_rom.segnum])
.ROM.Available  SET     (.ROM.Available + .ROM.SegAvlb[_rom.segnum])

_rom.segnum     QSET    (_rom.segnum + 1)

            ENDR
ENDM

;; ======================================================================== ;;
;;  __rom_init_segmem(seg, start, end, page, type)                          ;;
;;  Initializes and configures the requested memory map segment indicated   ;;
;;  by "seg," using the provided arguments.  All internal data structures   ;;
;;  for memory integrity and accounting are also initialized.               ;;
;;                                                                          ;;
;;                                                                          ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      seg         The number of the segment to initialize.                ;;
;;      start       The start address of the segment.                       ;;
;;      end         The end address of the segment.                         ;;
;;      page        An optional page number to switch the segment to.       ;;
;;      type        The type of segment:  "legacy," "static," or "dynamic". ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   __rom_init_segmem(seg, start, end, page, type)
;
                __rom_validate_type(%type%)
                __rom_assert_def_order(%type%)

        IF (_rom.error = _rom.null)

_rom.type           QSET    _rom.%type%
_rom.num            QSET    _rom.segcnt                 ; New internal segment number
_rom.segcnt         QSET    (_rom.segcnt + 1)           ; Total internal segments (so far)

            ; Keep track of the index for the given segment
            IF ((CLASSIFY(_rom.segidx[%seg%]) = -10000))
_rom.segs           QSET    (_rom.segs + 1)
_rom.segidx[%seg%]  QSET    _rom.num
_rom.bnkcnt[%seg%]  QSET    0
            ENDI

_rom.b   [_rom.num] QSET    %start%                     ; Start address
_rom.e   [_rom.num] QSET    %end%                       ; End address
_rom.p   [_rom.num] QSET    %page%                      ; Page number
_rom.t   [_rom.num] QSET    _rom.type                   ; Segment type

            IF ((%page%) <> _rom.invalid)

_rom.sbase          QSET    (_rom.b[_rom.num] AND $F000)
_rom.send           QSET    (_rom.e[_rom.num] OR  $0FFF)
_rom.spages         QSET    (((_rom.send - _rom.sbase) + 1) / _rom.pgsize)

_rom.pgs [_rom.num] QSET    _rom.spages                 ; Physical pages in segment

                ; For dynamic segments, keep track of
                ; the number of banks.
                IF (_rom.type = _rom.dynamic)
_rom.bnk [_rom.num] QSET    _rom.bnkcnt[%seg%]          ; Logical bank number
_rom.bnkcnt[%seg%]  QSET    (_rom.bnkcnt[%seg%] + 1)    ; Banks in segment
                ENDI

            ELSE

_rom.bnk [_rom.num] QSET    _rom.invalid
_rom.pgs [_rom.num] QSET    _rom.invalid

            ENDI

_rom.seg [_rom.num] QSET    %seg%
_rom.pos [_rom.num] QSET    %start%                     ; Starting position

.ROM.Segments[_rom.type] QSET   (.ROM.Segments[_rom.type] + 1)

            IF (_rom.type <> _rom.legacy)
                ; Initialize accounting statistics
                __rom_segmem_size     (_rom.num)
                __rom_segmem_used     (_rom.num)
                __rom_segmem_available(_rom.num)
            ENDI
        ENDI
ENDM

;; ======================================================================== ;;
;;  __rom_check_segmem_range(addr, segnum)                                  ;;
;;  Checks an address to make sure it falls within a given ROM segment.     ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      addr        The address to check.                                   ;;
;;      segnum      The internal segment for which to check the range.      ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;;      _rom.ovrflo The number of words in excess.                          ;;
;;      _rom.sidx   The logical segment number.                             ;;
;;      _rom.bidx   The logical bank number.                                ;;
;; ======================================================================== ;;
MACRO   __rom_check_segmem_range(addr, segnum)
;
        IF (_rom.open = %segnum%)
_rom.rbase      QSET    _rom.cb
_rom.rend       QSET    _rom.ce
        ELSE
_rom.rbase      QSET    _rom.b[%segnum%]
_rom.rend       QSET    _rom.e[%segnum%]
        ENDI


        IF _EXPMAC ((%addr%) < _rom.rbase) OR (((%addr%) - 1) > _rom.rend)

_rom.ovrflo     QSET    ((%addr%) - _rom.rend - 1)
_rom.sidx       QSET    _rom.seg[%segnum%]
_rom.bidx       QSET    _rom.bnk[%segnum%]

          ; NOTE: Overflows are significant, so we want to
          ;       display such errors in STDOUT as well.
          IF _EXPMAC (_rom.t[%segnum%] = _rom.dynamic)
            __rom_raise_error(["Dynamic ROM segment overflow in segment #", $#(_rom.sidx), ", bank #", $#(_rom.bidx)], ["Total ", $#(_rom.ovrflo), " words in excess."])

            SMSG $("ERROR: Overflow in dynamic ROM segment #", $#(_rom.sidx), ", bank #", $#(_rom.bidx), ": Total ", $#(_rom.ovrflo), " words in excess.")
          ELSE
            __rom_raise_error(["ROM segment overflow in segment #", $#(_rom.sidx)], ["Total ", $#(_rom.ovrflo), " words in excess."])

            SMSG $("ERROR: Overflow in ROM segment #", $#(_rom.sidx), ": Total ", $#(_rom.ovrflo), " words in excess.")
          ENDI
        ENDI
ENDM

;; ======================================================================== ;;
;;  __rom_set_pc_addrs(addr, page)                                          ;;
;;  Relocates the program counter to the given address, selecting a         ;;
;;  specific page if requested.                                             ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      addr        The new address to set the program counter.             ;;
;;      page        An optional page to select (or _rom.invalid if none).   ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      None.                                                               ;;
;; ======================================================================== ;;
MACRO   __rom_set_pc_addrs(addr, page)
;
        IF (%page% <> _rom.invalid)

            LISTING "on"
                ; Open segment page
                ORG     %addr%:%page%
            LISTING "prev"

        ELSE

            LISTING "on"
                ; Open segment
                ORG     %addr%
            LISTING "prev"

        ENDI
ENDM

;; ======================================================================== ;;
;;  __rom_open_seg(segnum)                                                  ;;
;;  Opens a ROM segment.  If the segment is already open, it checks the     ;;
;;  current program counter to ensure it is still within valid range.       ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      segnum      The internal memory map segment to open.                ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   __rom_open_seg(segnum)
;
                __rom_reset_error
                __rom_validate_segnum(%segnum%)

        IF _EXPMAC (_rom.error = _rom.null)

            IF _EXPMAC (_rom.open <> %segnum%)

_rom.cb         QSET    _rom.b  [%segnum%]      ; Current base address
_rom.ce         QSET    _rom.e  [%segnum%]      ; Current end address
_rom.cp         QSET    _rom.p  [%segnum%]      ; Current page

_rom.cpos       QSET    _rom.pos[%segnum%]

                __rom_set_pc_addrs(_rom.cpos, _rom.cp)

_rom.open       QSET    %segnum%
.ROM.CurrentSeg QSET    _rom.open

            ELSE

_rom.pc         QSET    $

                ; If the segment is already open, just
                ; verify we're still within in range.
                __rom_check_segmem_range(_rom.pc, %segnum%)

            ENDI

        ENDI
ENDM

;; ======================================================================== ;;
;;  __rom_close_seg(segnum)                                                 ;;
;;  Closes an open ROM segment.  It also checks that the current program    ;;
;;  counter falls within the valid range of the open segment.  Nothing will ;;
;;  be done if "segnum" is _rom.invalid.  An error is raised if the given   ;;
;;  segment is not open.                                                    ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      segnum      The internal memory map segment to close.               ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   __rom_close_seg(segnum)
;
                __rom_reset_error

        IF ((%segnum%) <> _rom.invalid)

                __rom_validate_segnum(%segnum%)

          IF (_rom.error = _rom.null)

            IF (_rom.open <> %segnum%)
                IF (_rom.t[%segnum%] = _rom.dynamic)
                  __rom_raise_error("Dynamic ROM segment closure failed", ["Bank #", $#(_rom.bnk[%segnum%]), " is not opened."])
                ELSE
                  __rom_raise_error("ROM segment closure failed", ["Segment #", $#(_rom.seg[%segnum%]), " is not opened."])
                ENDI
            ELSE

_rom.pc             QSET $

              ; Ignore legacy segments
              IF (_rom.t[%segnum%] <> _rom.legacy)

                ; Close segment
                __rom_check_segmem_range(_rom.pc, %segnum%)

                ; Keep track of current segment position
_rom.pos[%segnum%]  QSET _rom.pc

                ; Compute usage statistics
                __rom_segmem_used(%segnum%)
                __rom_segmem_available(%segnum%)

              ENDI

_rom.open           QSET _rom.invalid                   ; Close segment %segnum%
.ROM.CurrentSeg     QSET _rom.open

            ENDI

          ENDI

        ENDI
ENDM

;; ======================================================================== ;;
;;  __rom_try_open_seg(segnum, min)                                         ;;
;;  Opens a given ROM segment if it has a minimum of "min" words available. ;;
;;                                                                          ;;
;;  NOTE:   If a ROM segment is currently opened, this macro will not do    ;;
;;          anything.  This lets us chain calls to __rom_try_open_seg() for ;;
;;          all available segments, in order to attempt to find one with    ;;
;;          sufficient capacity.                                            ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      segnum      The internal memory map segment to test and open.       ;;
;;      min         The minimum size required, in 16-bit words.             ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   __rom_try_open_seg(segnum, min)
;
        IF _EXPMAC ((_rom.open = _rom.invalid) AND (%segnum% < _rom.segcnt) AND ((_rom.pos[%segnum%] + (%min%)) < _rom.e[%segnum%]))
                __rom_open_seg(%segnum%)
        ENDI
ENDM

;; ======================================================================== ;;
;;  __rom_select_segment(seg)                                               ;;
;;  Relocates the program counter to a static ROM segment.  Also closes the ;;
;;  currently open segment, keeping track of its usage.                     ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      seg         The static ROM segment to open.                         ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   __rom_select_segment(seg)
;
        IF (_rom.error = _rom.null)
                __rom_validate_segment(%seg%)
        ENDI

        IF (_rom.error = _rom.null)

_rom.segnum     QSET    _rom.segidx[%seg%]
_rom.type       QSET    _rom.t[_rom.segnum]

            ; Fail if the segment is dynamic
            IF (_rom.type = _rom.dynamic)
                __rom_raise_error(["Cannot select ROM segment #", $#(%seg%), " without a bank"], "Segment is dynamic.")
            ENDI

            ; Open static segment
            IF (_rom.type = _rom.static)
                __rom_close_seg(_rom.open)
                __rom_open_seg(_rom.segnum)
            ENDI

        ENDI
ENDM

;; ======================================================================== ;;
;;  __rom_switch_mem_page(base, page)                                       ;;
;;  Switches a range of memory addresses to a target page.                  ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      base        The base address of the range to switch.                ;;
;;      page        The target page number.                                 ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   __rom_switch_mem_page(base, page)
;
_rom.b_addr     QSET    ((%base%) AND $F000)
_rom.b_src      QSET    (_rom.b_addr OR $0A50 OR (%page%))
_rom.b_trg      QSET    (_rom.b_addr OR $0FFF)

    LISTING "on"

                MVII    #_rom.b_src, R0                 ; \_ Switch bank: [$s000 - $sFFF] to page
                MVO     R0,     _rom.b_trg              ; /

    LISTING "prev"
ENDM

;; ======================================================================== ;;
;;  __rom_stats_scale(val, scale)                                           ;;
;;  Returns value "val" scaled by "scale." The formula used for scaling is: ;;
;;                                                                          ;;
;;              return = ceil(val / scale)                                  ;;
;;                     = [((val * base) / scale) + (base - 1)] / base       ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      val         The value to scale.                                     ;;
;;      scale       The scale to apply.                                     ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      ceil(val / scale).                                                  ;;
;; ======================================================================== ;;
MACRO   __rom_stats_scale(val, scale)
    (((((%val%) * 10) / (%scale%)) + 9) / 10)
ENDM

;; ======================================================================== ;;
;;  __rom_stats_draw_line(style, len)                                       ;;
;;  Outputs a horizontal line, useful for displaying tabular information.   ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      style       The line style to draw.  Available values are:          ;;
;;                      single      Single (thin) line.                     ;;
;;                      double      Double (thick) line.                    ;;
;;                                                                          ;;
;;      len         The length of the line to draw, in characters.          ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      A horizontal line in the given style.                               ;;
;; ======================================================================== ;;
MACRO   __rom_stats_draw_line(style, len)
        _rom_stat.%style%[0, ((%len%) - 1)]
ENDM

;; ======================================================================== ;;
;;  __rom_stats_pad_left(str, len)                                          ;;
;;  Outputs a string in a field of "len" characters, justified to the right ;;
;;  and padded on the left with blank spaces.                               ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      str         The string to output.                                   ;;
;;      len         The length of the field, in characters.                 ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      The string, left-padded in the field.                               ;;
;; ======================================================================== ;;
MACRO   __rom_stats_pad_left(str, len)
        $(_rom_stat.space[0, ((%len%) - STRLEN(%str%) - 1)], %str%)
ENDM

;; ======================================================================== ;;
;;  __rom_stats_pad_right(str, len)                                         ;;
;;  Outputs a string in a field of "len" characters, justified to the left  ;;
;;  and padded on the right with blank spaces.                              ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      str         The string to output.                                   ;;
;;      len         The length of the field, in characters.                 ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      The string, right-padded in the field.                              ;;
;; ======================================================================== ;;
MACRO   __rom_stats_pad_right(str, len)
        $(%str%, _rom_stat.space[0, ((%len%) - STRLEN(%str%) - 1)])
ENDM

;; ======================================================================== ;;
;;  ROM.Setup map                                                           ;;
;;  Configures and initializes the memory map indicated by "map."           ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      map         The memory map number to initialize.                    ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   ROM.Setup map
;
    LISTING "code"

                __rom_reset_error

        ; Make sure the directive is called only once!
        IF ((CLASSIFY(_rom.init) = -10000))
                __rom_validate_map(%map%)
        ELSE
                __rom_raise_error(["ROM", ".Setup directive must be called only once per program."], _rom.null)
        ENDI

        IF (_rom.error = _rom.null)

_rom.init       QEQU    1
_rom.map        QSET    %map%
_rom.ecs_off    QSET    _rom.null
_rom.extra_rom  QSET    0

            IF (intybasic_ecs)
_rom.ecs_req    QSET    intybasic_ecs
            ELSE
_rom.ecs_req    QSET    _rom.null
            ENDI

            IF (intybasic_jlp)
_rom.jlp_req    QSET    intybasic_jlp
            ELSE
_rom.jlp_req    QSET    _rom.null
            ENDI

            IF (intybasic_cc3 OR intybasic_jlp)
_rom.cart_ram   QSET    1
            ELSE
_rom.cart_ram   QSET    _rom.null
            ENDI

            ; ---------------------------------------------------------
            ; Initialize ROM segments for active memory map.
            ;
            ; NOTE: Define below the segments available for each memory
            ;       map supported.  When defining a map, the following
            ;       rules must be observed:
            ;
            ;         - Map #0 must always be the "legacy" map.
            ;         - All static segments in a map must be defined
            ;           before any dynamic ones.
            ;         - Segment numbers must start at zero.
            ;         - Segment numbers should be defined in order.
            ;         - There must not be gaps in segment numbers.
            ; ---------------------------------------------------------

            ; MAP #0: Legacy memory map wit no ROM management
            IF (_rom.map = 0)
                __rom_init_segmem(0, $5000, $FFFF, _rom.invalid, legacy)
            ENDI

            ; MAP #1: Original Mattel 16K static memory map
            IF (_rom.map = 1)
                __rom_init_segmem(0, $5000, $6FFF, _rom.invalid, static)
                __rom_init_segmem(1, $D000, $DFFF, _rom.invalid, static)
                __rom_init_segmem(2, $F000, $FFFF, _rom.invalid, static)
            ENDI

            ; MAP #2: JLP 42K static memory map
            IF (_rom.map = 2)
_rom.ecs_off    QSET    1

                __rom_init_segmem(0, $5000, $6FFF, _rom.invalid, static)
                __rom_init_segmem(1, $A000, $BFFF, _rom.invalid, static)
                __rom_init_segmem(2, $C040, $FFFF, _rom.invalid, static)

              IF (_rom.jlp_req <> _rom.null)
                __rom_init_segmem(3, $2000, $2FFF, $F,           static)
                __rom_init_segmem(4, $7000, $7FFF, $F,           static)
              ELSE
                __rom_init_segmem(3, $2100, $2FFF, _rom.invalid, static)
                __rom_init_segmem(4, $7100, $7FFF, _rom.invalid, static)
              ENDI

                __rom_init_segmem(5, $4810, $4FFF, _rom.invalid, static)
            ENDI

            ; MAP #3: Dynamic bank-switching 98K memory map - 4K banks
            IF (_rom.map = 3)
_rom.ecs_off    QSET    1

                __rom_init_segmem(0, $5000, $6FFF, _rom.invalid, static)
                __rom_init_segmem(1, $A000, $BFFF, _rom.invalid, static)
                __rom_init_segmem(2, $C040, $FFFF, _rom.invalid, static)
                __rom_init_segmem(3, $2000, $2FFF, $F,           static)
                __rom_init_segmem(4, $4810, $4FFF, _rom.invalid, static)

_rom.dynseg     QSET    _rom.segcnt

                __rom_init_segmem(_rom.dynseg, $7000, $7FFF, $1, dynamic)
                __rom_init_segmem(_rom.dynseg, $7000, $7FFF, $2, dynamic)
                __rom_init_segmem(_rom.dynseg, $7000, $7FFF, $3, dynamic)
                __rom_init_segmem(_rom.dynseg, $7000, $7FFF, $4, dynamic)
                __rom_init_segmem(_rom.dynseg, $7000, $7FFF, $5, dynamic)
                __rom_init_segmem(_rom.dynseg, $7000, $7FFF, $6, dynamic)
                __rom_init_segmem(_rom.dynseg, $7000, $7FFF, $7, dynamic)
                __rom_init_segmem(_rom.dynseg, $7000, $7FFF, $8, dynamic)
                __rom_init_segmem(_rom.dynseg, $7000, $7FFF, $9, dynamic)
                __rom_init_segmem(_rom.dynseg, $7000, $7FFF, $A, dynamic)
                __rom_init_segmem(_rom.dynseg, $7000, $7FFF, $B, dynamic)
                __rom_init_segmem(_rom.dynseg, $7000, $7FFF, $C, dynamic)
                __rom_init_segmem(_rom.dynseg, $7000, $7FFF, $D, dynamic)
                __rom_init_segmem(_rom.dynseg, $7000, $7FFF, $E, dynamic)
                __rom_init_segmem(_rom.dynseg, $7000, $7FFF, $F, dynamic)
            ENDI

            ; MAP #4: Dynamic bank-switching 154K memory map - 8K banks
            IF (_rom.map = 4)
_rom.ecs_off    QSET    1

                __rom_init_segmem(0, $5000, $6FFF, _rom.invalid, static)
                __rom_init_segmem(1, $A000, $BFFF, _rom.invalid, static)
                __rom_init_segmem(2, $C040, $DFFF, _rom.invalid, static)
                __rom_init_segmem(3, $2000, $2FFF, $F,           static)
                __rom_init_segmem(4, $7000, $7FFF, $F,           static)
                __rom_init_segmem(5, $4810, $4FFF, _rom.invalid, static)

_rom.dynseg     QSET    _rom.segcnt

                __rom_init_segmem(_rom.dynseg, $E000, $FFFF, $0, dynamic)
                __rom_init_segmem(_rom.dynseg, $E000, $FFFF, $2, dynamic)
                __rom_init_segmem(_rom.dynseg, $E000, $FFFF, $3, dynamic)
                __rom_init_segmem(_rom.dynseg, $E000, $FFFF, $4, dynamic)
                __rom_init_segmem(_rom.dynseg, $E000, $FFFF, $5, dynamic)
                __rom_init_segmem(_rom.dynseg, $E000, $FFFF, $6, dynamic)
                __rom_init_segmem(_rom.dynseg, $E000, $FFFF, $7, dynamic)
                __rom_init_segmem(_rom.dynseg, $E000, $FFFF, $8, dynamic)
                __rom_init_segmem(_rom.dynseg, $E000, $FFFF, $9, dynamic)
                __rom_init_segmem(_rom.dynseg, $E000, $FFFF, $A, dynamic)
                __rom_init_segmem(_rom.dynseg, $E000, $FFFF, $B, dynamic)
                __rom_init_segmem(_rom.dynseg, $E000, $FFFF, $C, dynamic)
                __rom_init_segmem(_rom.dynseg, $E000, $FFFF, $D, dynamic)
                __rom_init_segmem(_rom.dynseg, $E000, $FFFF, $E, dynamic)
                __rom_init_segmem(_rom.dynseg, $E000, $FFFF, $F, dynamic)
            ENDI

            ; MAP #5: Dynamic bank-switching 254K memory map - 16K banks
            IF (_rom.map = 5)
_rom.ecs_off    QSET    1

                __rom_init_segmem(0, $5000, $6FFF, _rom.invalid, static)
                __rom_init_segmem(1, $A000, $BFFF, _rom.invalid, static)
                __rom_init_segmem(2, $2000, $2FFF, $F,           static)
                __rom_init_segmem(3, $7000, $7FFF, $F,           static)
                __rom_init_segmem(4, $4810, $4FFF, _rom.invalid, static)

_rom.dynseg     QSET    _rom.segcnt

                __rom_init_segmem(_rom.dynseg, $C040, $FFFF, $0, dynamic)
                __rom_init_segmem(_rom.dynseg, $C040, $FFFF, $2, dynamic)
                __rom_init_segmem(_rom.dynseg, $C040, $FFFF, $3, dynamic)
                __rom_init_segmem(_rom.dynseg, $C040, $FFFF, $4, dynamic)
                __rom_init_segmem(_rom.dynseg, $C040, $FFFF, $5, dynamic)
                __rom_init_segmem(_rom.dynseg, $C040, $FFFF, $6, dynamic)
                __rom_init_segmem(_rom.dynseg, $C040, $FFFF, $7, dynamic)
                __rom_init_segmem(_rom.dynseg, $C040, $FFFF, $8, dynamic)
                __rom_init_segmem(_rom.dynseg, $C040, $FFFF, $9, dynamic)
                __rom_init_segmem(_rom.dynseg, $C040, $FFFF, $A, dynamic)
                __rom_init_segmem(_rom.dynseg, $C040, $FFFF, $B, dynamic)
                __rom_init_segmem(_rom.dynseg, $C040, $FFFF, $C, dynamic)
                __rom_init_segmem(_rom.dynseg, $C040, $FFFF, $D, dynamic)
                __rom_init_segmem(_rom.dynseg, $C040, $FFFF, $E, dynamic)
            ENDI

            ; MAP #6: Dynamic bank-switching 256K map -- 2 dynamic segments
            IF (_rom.map = 6)
_rom.ecs_off    QSET    1

                __rom_init_segmem(0, $5000, $6FFF, _rom.invalid, static)
                __rom_init_segmem(1, $C040, $DFFF, _rom.invalid, static)

                __rom_init_segmem(2, $A000, $BFFF, $0,           dynamic)
                __rom_init_segmem(2, $A000, $BFFF, $1,           dynamic)
                __rom_init_segmem(2, $A000, $BFFF, $2,           dynamic)
                __rom_init_segmem(2, $A000, $BFFF, $3,           dynamic)
                __rom_init_segmem(2, $A000, $BFFF, $4,           dynamic)
                __rom_init_segmem(2, $A000, $BFFF, $5,           dynamic)
                __rom_init_segmem(2, $A000, $BFFF, $6,           dynamic)
                __rom_init_segmem(2, $A000, $BFFF, $7,           dynamic)
                __rom_init_segmem(2, $A000, $BFFF, $8,           dynamic)
                __rom_init_segmem(2, $A000, $BFFF, $9,           dynamic)
                __rom_init_segmem(2, $A000, $BFFF, $A,           dynamic)
                __rom_init_segmem(2, $A000, $BFFF, $B,           dynamic)
                __rom_init_segmem(2, $A000, $BFFF, $C,           dynamic)
                __rom_init_segmem(2, $A000, $BFFF, $D,           dynamic)
                __rom_init_segmem(2, $A000, $BFFF, $E,           dynamic)

                __rom_init_segmem(3, $E000, $FFFF, $0,           dynamic)
                __rom_init_segmem(3, $E000, $FFFF, $2,           dynamic)
                __rom_init_segmem(3, $E000, $FFFF, $3,           dynamic)
                __rom_init_segmem(3, $E000, $FFFF, $4,           dynamic)
                __rom_init_segmem(3, $E000, $FFFF, $5,           dynamic)
                __rom_init_segmem(3, $E000, $FFFF, $6,           dynamic)
                __rom_init_segmem(3, $E000, $FFFF, $7,           dynamic)
                __rom_init_segmem(3, $E000, $FFFF, $8,           dynamic)
                __rom_init_segmem(3, $E000, $FFFF, $9,           dynamic)
                __rom_init_segmem(3, $E000, $FFFF, $A,           dynamic)
                __rom_init_segmem(3, $E000, $FFFF, $B,           dynamic)
                __rom_init_segmem(3, $E000, $FFFF, $C,           dynamic)
                __rom_init_segmem(3, $E000, $FFFF, $D,           dynamic)
                __rom_init_segmem(3, $E000, $FFFF, $E,           dynamic)
                __rom_init_segmem(3, $E000, $FFFF, $F,           dynamic)
            ENDI


            ; MAP #7: Dynamic bank-switching 238K map -- 4 dynamic segments
            IF (_rom.map = 7)
_rom.ecs_off    QSET    1

                __rom_init_segmem(0, $5000, $6FFF, _rom.invalid, static)
                __rom_init_segmem(1, $2000, $2FFF, $F,           static)
                __rom_init_segmem(2, $4810, $4FFF, _rom.invalid, static)

                __rom_init_segmem(3, $7000, $7FFF, $1,           dynamic)
                __rom_init_segmem(3, $7000, $7FFF, $2,           dynamic)
                __rom_init_segmem(3, $7000, $7FFF, $3,           dynamic)
                __rom_init_segmem(3, $7000, $7FFF, $4,           dynamic)
                __rom_init_segmem(3, $7000, $7FFF, $5,           dynamic)
                __rom_init_segmem(3, $7000, $7FFF, $6,           dynamic)
                __rom_init_segmem(3, $7000, $7FFF, $7,           dynamic)
                __rom_init_segmem(3, $7000, $7FFF, $8,           dynamic)

                __rom_init_segmem(4, $A000, $BFFF, $0,           dynamic)
                __rom_init_segmem(4, $A000, $BFFF, $1,           dynamic)
                __rom_init_segmem(4, $A000, $BFFF, $2,           dynamic)
                __rom_init_segmem(4, $A000, $BFFF, $3,           dynamic)
                __rom_init_segmem(4, $A000, $BFFF, $4,           dynamic)
                __rom_init_segmem(4, $A000, $BFFF, $5,           dynamic)
                __rom_init_segmem(4, $A000, $BFFF, $6,           dynamic)
                __rom_init_segmem(4, $A000, $BFFF, $7,           dynamic)

                __rom_init_segmem(5, $C040, $DFFF, $0,           dynamic)
                __rom_init_segmem(5, $C040, $DFFF, $1,           dynamic)
                __rom_init_segmem(5, $C040, $DFFF, $2,           dynamic)
                __rom_init_segmem(5, $C040, $DFFF, $3,           dynamic)
                __rom_init_segmem(5, $C040, $DFFF, $4,           dynamic)
                __rom_init_segmem(5, $C040, $DFFF, $5,           dynamic)
                __rom_init_segmem(5, $C040, $DFFF, $6,           dynamic)
                __rom_init_segmem(5, $C040, $DFFF, $7,           dynamic)

                __rom_init_segmem(6, $E000, $FFFF, $0,           dynamic)
                __rom_init_segmem(6, $E000, $FFFF, $2,           dynamic)
                __rom_init_segmem(6, $E000, $FFFF, $3,           dynamic)
                __rom_init_segmem(6, $E000, $FFFF, $4,           dynamic)
                __rom_init_segmem(6, $E000, $FFFF, $5,           dynamic)
                __rom_init_segmem(6, $E000, $FFFF, $6,           dynamic)
                __rom_init_segmem(6, $E000, $FFFF, $7,           dynamic)
                __rom_init_segmem(6, $E000, $FFFF, $8,           dynamic)
            ENDI

            ; MAP #8: 50K static memory map
            IF (_rom.map = 8)
_rom.extra_rom  QSET    1

                __rom_init_segmem(0, $5000, $6FFF, _rom.invalid, static)
                __rom_init_segmem(1, $A000, $BFFF, _rom.invalid, static)
                __rom_init_segmem(2, $C040, $FFFF, _rom.invalid, static)
                __rom_init_segmem(3, $2100, $2FFF, _rom.invalid, static)
                __rom_init_segmem(4, $7100, $7FFF, _rom.invalid, static)

                __rom_init_segmem(5, $4810, $4FFF, _rom.invalid, static)
                __rom_init_segmem(6, $8040, $9FFF, _rom.invalid, static)
            ENDI

        ENDI

        ; Check if cartridge RAM conflicts with extra ROM at $8040
        IF (_rom.cart_ram AND _rom.extra_rom)
          __rom_raise_error(["Map #", $#(_rom.map), " is not compatible with JLP or CC3 cartridge RAM."], _rom.null)

          SMSG $("ERROR: Map #", $#(_rom.map), " is not compatible with JLP or CC3 cartridge RAM.")
        ENDI

        IF (_rom.error = _rom.null)

                ; Disable ECS in advanced maps and when ECS is used.
            IF ((_rom.ecs_off <> _rom.null) OR (_rom.ecs_req))
                __rom_set_pc_addrs($4800, _rom.invalid) ; Set up bootstrap hook

                __rom_switch_mem_page($2000, $F)        ; \
                __rom_switch_mem_page($7000, $F)        ;  > Switch off ECS ROMs
                __rom_switch_mem_page($E000, $F)        ; /

                B       $1041                           ; resume boot
            ENDI

                ; Initialize ROM base to segment #0
                ;   ($5000 - $6FFF in all maps)
                __rom_open_seg(0)

                ; ------------------------------------------------
                ; Configure the ROM header (Universal Data Block)
                ; ------------------------------------------------
                BIDECLE _ZERO           ; MOB picture base
                BIDECLE _ZERO           ; Process table
                BIDECLE _MAIN           ; Program start
                BIDECLE _ZERO           ; Background base image
                BIDECLE _ONES           ; GRAM
                BIDECLE _TITLE          ; Cartridge title and date
                DECLE   $03C0           ; No ECS title, jump to code after title,
                                        ; ... no clicks

_ZERO:          DECLE   $0000           ; Border control
                DECLE   $0000           ; 0 = color stack, 1 = f/b mode

_ONES:          DECLE   $0001, $0001    ; Initial color stack 0 and 1: Blue
                DECLE   $0001, $0001    ; Initial color stack 2 and 3: Blue
                DECLE   $0001           ; Initial border color: Blue

        ENDI

    LISTING "prev"
ENDM

;; ======================================================================== ;;
;;  ROM.SelectDefaultSegment                                                ;;
;;  Relocates the program counter to the default ROM segment (#0).  Also    ;;
;;  closes the currently open segment, keeping track of its usage.          ;;
;;                                                                          ;;
;;  The macro will do nothing when the legacy map (#0) is selected.         ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      None.                                                               ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   ROM.SelectDefaultSegment
;
    LISTING "code"

                __rom_reset_error
                __rom_assert_setup("SelectSegment")

        IF (_rom.error = _rom.null)

            ; Ignore when the legacy map is selected
            IF (_rom.map > 0)
                __rom_select_segment(0)
            ENDI

        ENDI

    LISTING "prev"
ENDM

;; ======================================================================== ;;
;;  ROM.SelectSegment seg                                                   ;;
;;  Relocates the program counter to a static ROM segment.  Also closes the ;;
;;  currently open segment, keeping track of its usage.                     ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      seg         The static ROM segment to open.                         ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   ROM.SelectSegment seg
;
    LISTING "code"

                __rom_reset_error
                __rom_assert_romseg_support("Segment selection")
                __rom_assert_setup("SelectSegment")

        IF (_rom.error = _rom.null)
                __rom_select_segment(%seg%)
        ENDI

    LISTING "prev"
ENDM

;; ======================================================================== ;;
;;  ROM.SelectBank seg, bank                                                ;;
;;  Relocates the program counter to a dynamic ROM segment bank.  Also      ;;
;;  closes the currently open segment, keeping track of its usage.          ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      seg         The dynamic ROM segment, or -1 for the first one.       ;;
;;      bank        The segment bank number to open.                        ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   ROM.SelectBank seg, bank
;
    LISTING "code"

                __rom_reset_error
                __rom_assert_romseg_support("Dynamic segment bank selection")
                __rom_assert_setup("SelectBank")

        IF (_rom.error = _rom.null)

            ; Determine the logical segment number
            IF ((%seg%) = _rom.invalid)
_rom.num        QSET    .ROM.Segments[_rom.static]
            ELSE
_rom.num        QSET    %seg%
            ENDI

_rom.type       QSET    _rom.t[_rom.num]

            ; Fail if the segment is not dynamic
            IF (_rom.type <> _rom.dynamic)
                __rom_raise_error(["Cannot select bank on ROM segment #", $#(_rom.num)], "Segment is not dynamic.")
            ENDI

            ; Validate the segment and bank
            IF (_rom.error = _rom.null)
                __rom_validate_seg_bank(_rom.num, %bank%)
            ENDI

            IF (_rom.error = _rom.null)

_rom.segnum     QSET    (_rom.segidx[_rom.num] + (%bank%))

              IF (_rom.segnum <> _rom.open)
                ; Open dynamic segment bank
                IF (_rom.error = _rom.null)
                  __rom_close_seg(_rom.open)
                  __rom_open_seg(_rom.segnum)
                ENDI
              ENDI

            ENDI

        ENDI

    LISTING "prev"
ENDM

;; ======================================================================== ;;
;;  ROM.AutoSelectSegment min                                               ;;
;;  Finds a static ROM segment with the specified minimum available         ;;
;;  capacity, and relocates the program counter to it.  Also closes the     ;;
;;  currently open segment, keeping track of its usage statistics.          ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      min         The minimum capacity required, in 16-bit words.         ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   ROM.AutoSelectSegment min
;
    LISTING "code"

                __rom_reset_error
                __rom_assert_romseg_support("Automatic segment selection")
                __rom_assert_setup("AutoSelectSegment")

        IF (_rom.error = _rom.null)
                __rom_close_seg(_rom.open)
        ENDI

        IF (_rom.error = _rom.null)

_rom.segnum     QSET    0

            REPEAT (.ROM.Segments[_rom.static])
                __rom_try_open_seg(_rom.segnum, %min%)

_rom.segnum     QSET    (_rom.segnum + 1)
            ENDR

            ; Fail if no segment was found with enough space
            IF (_rom.open = _rom.invalid)
                __rom_raise_error("Automatic ROM segment selection failed", ["Could not find a suitable segment with ", $#(%min%), " words available."])
            ENDI

        ENDI

    LISTING "prev"
ENDM

;; ======================================================================== ;;
;;  ROM.SwitchBank seg, bank                                                ;;
;;  Switches a dynamic ROM segment to the requested bank.                   ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      seg         The dynamic ROM segment, or -1 for the first one.       ;;
;;      bank        The dynamic ROM segment bank number to activate.        ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   ROM.SwitchBank seg, bank
;
    LISTING "code"

                __rom_reset_error
                __rom_assert_romseg_support("Automatic segment selection")
                __rom_assert_setup("SwitchBank")

        IF (_rom.error = _rom.null)

            ; Determine the logical segment number
            IF ((%seg%) = _rom.invalid)
_rom.num        QSET    .ROM.Segments[_rom.static]
            ELSE
_rom.num        QSET    %seg%
            ENDI

_rom.type       QSET    _rom.t[_rom.num]

            ; Fail if the segment is not dynamic
            IF (_rom.type <> _rom.dynamic)
                __rom_raise_error(["Cannot switch bank on ROM segment #", $#(_rom.num)], "Segment is not dynamic.")
            ENDI

            ; Validate the segment and bank
            IF (_rom.error = _rom.null)
                __rom_validate_seg_bank(_rom.num, %bank%)
            ENDI

            IF (_rom.error = _rom.null)

_rom.segnum     QSET    (_rom.segidx[_rom.num] + (%bank%))

                ; Initialize REPEAT loop symbols
_rom.r_pgs      QSET    _rom.pgs[_rom.segnum]
_rom.r_addr     QSET    _rom.b  [_rom.segnum]
_rom.r_page     QSET    _rom.p  [_rom.segnum]

                ; Switch the physical pages that comprise
                ; the logical segment bank.
                REPEAT (_rom.r_pgs)
                    __rom_switch_mem_page(_rom.r_addr, _rom.r_page)
_rom.r_addr         QSET    (_rom.r_addr + _rom.pgsize)
                ENDR

            ENDI

        ENDI

    LISTING "prev"
ENDM


;; ======================================================================== ;;
;;  ROM.End                                                                 ;;
;;  Closes any open ROM segment, reports usage statistics, and finalizes    ;;
;;  the program.                                                            ;;
;;                                                                          ;;
;;  This macro must be called at the very end of the program.               ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      None.                                                               ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      _rom.error  -1 on failure.                                          ;;
;; ======================================================================== ;;
MACRO   ROM.End
;
    LISTING "code"

                __rom_reset_error
                __rom_assert_setup("End")

        IF (_rom.error = _rom.null)
                __rom_close_seg(_rom.open)

            ; The legacy map does not support usage statistics
            IF (_rom.map > 0)
                __rom_calculate_stats
            ENDI
        ENDI

    LISTING "prev"
ENDM

;; ======================================================================== ;;
;;  ROM.OutputRomStats                                                      ;;
;;  Outputs ROM usage statistics to STDOUT and to the listing file.         ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      None.                                                               ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      ROM usage statistics.                                               ;;
;; ======================================================================== ;;
MACRO   ROM.OutputRomStats
;
    LISTING "code"

_rom.hdr_len    QSET    55
_rom.fld_ttl    QSET    15
_rom.fld_mem    QSET    7
_rom.fld_bnk    QSET    3
_rom.fld_siz    QSET    4
_rom.fld_avl    QSET    8
_rom.scale      QSET    1024

_rom.static_sz  QSET    0
_rom.static_us  QSET    0
_rom.static_av  QSET    0

      IF (_rom.map > 0)

                ; Draw header
                SMSG ""
                SMSG $("ROM USAGE (MAP #", $#(_rom.map), "):")
                SMSG    $("    ", __rom_stats_draw_line(double, _rom.hdr_len))
                SMSG    $("    ", "    Segment        Size       Used      Available")
                SMSG    $("    ", __rom_stats_draw_line(double, _rom.hdr_len))

_rom.idx        QSET    0
_rom.cnt        QSET    .ROM.Segments[_rom.static]

        ; Static segments
        REPEAT (_rom.cnt)
_rom.segnum     QSET    _rom.segidx[_rom.idx]

_rom.size       QSET    .ROM.SegSize[_rom.segnum]
_rom.used       QSET    .ROM.SegUsed[_rom.segnum]
_rom.avlb       QSET    .ROM.SegAvlb[_rom.segnum]

_rom.size       QSET    __rom_stats_scale(_rom.size, _rom.scale)    ; Scaled to 1K

                ; Static ROM segment stats
                SMSG    $("    ", "Static Seg #", $#(_rom.idx), "     ", __rom_stats_pad_left($#(_rom.size), _rom.fld_siz), "K     ", __rom_stats_pad_left($#(_rom.used), _rom.fld_mem), "  ", __rom_stats_pad_left($#(_rom.avlb), _rom.fld_avl), " words")

_rom.static_sz  QSET    (_rom.static_sz + _rom.size)
_rom.static_us  QSET    (_rom.static_us + _rom.used)
_rom.static_av  QSET    (_rom.static_av + _rom.avlb)

_rom.idx        QSET    (_rom.idx + 1)
        ENDR

_rom.cnt        QSET    (_rom.segs - _rom.idx)

        ; Report static sub-total if there are dynamic segments.
        ; (When there are no dynamic segments, the final account
        ; is the total for static segments.)
        IF (_rom.cnt > 0)
                ; Draw footer
                SMSG    $("    ", __rom_stats_draw_line(single, _rom.hdr_len))
                SMSG    $("    ", __rom_stats_pad_left("SUB-TOTAL:", _rom.fld_ttl), "   ", __rom_stats_pad_left($#(_rom.static_sz), _rom.fld_siz), "K     ", __rom_stats_pad_left($#(_rom.static_us), _rom.fld_mem), "  ", __rom_stats_pad_left($#(_rom.static_av), _rom.fld_avl), " words")
        ENDI

        ; Dynamic segments
        REPEAT (_rom.cnt)
_rom.segnum     QSET    _rom.segidx[_rom.idx]

                ; Dynamic ROM segment header
                SMSG    $("    ", __rom_stats_draw_line(single, _rom.hdr_len))
                SMSG    $("    ", "Dynamic Seg #", $#(_rom.idx), ":")

_rom.bidx       QSET    0
_rom.bcnt       QSET    _rom.bnkcnt[_rom.idx]

            ; Dynamic segment banks
            REPEAT (_rom.bcnt)

_rom.segnum     QSET    (_rom.segidx[_rom.idx] + _rom.bidx)

_rom.size       QSET    .ROM.SegSize[_rom.segnum]
_rom.used       QSET    .ROM.SegUsed[_rom.segnum]
_rom.avlb       QSET    .ROM.SegAvlb[_rom.segnum]

_rom.size       QSET    __rom_stats_scale(_rom.size, _rom.scale)    ; Scaled to 1K

                SMSG    $("    ", "       Bank #", __rom_stats_pad_right($#(_rom.bidx), _rom.fld_bnk), "  ", __rom_stats_pad_left($#(_rom.size), _rom.fld_siz), "K     ", __rom_stats_pad_left($#(_rom.used), _rom.fld_mem), "  ", __rom_stats_pad_left($#(_rom.avlb), _rom.fld_avl), " words")

_rom.bidx       QSET    (_rom.bidx + 1)
            ENDR

_rom.idx        QSET    (_rom.idx + 1)
        ENDR

_rom.size       QSET    __rom_stats_scale(.ROM.Size, _rom.scale)    ; Scaled to 1K

                ; Draw footer
                SMSG    $("    ", __rom_stats_draw_line(double, _rom.hdr_len))
                SMSG    $("    ", __rom_stats_pad_left("TOTAL:", _rom.fld_ttl), "   ", __rom_stats_pad_left($#(_rom.size), _rom.fld_siz), "K     ", __rom_stats_pad_left($#(.ROM.Used), _rom.fld_mem), "  ", __rom_stats_pad_left($#(.ROM.Available), _rom.fld_avl), " words")
                SMSG    $("    ", __rom_stats_draw_line(double, _rom.hdr_len))
                SMSG ""

      ENDI

    LISTING "prev"
ENDM

;; ======================================================================== ;;
;;  EOF: romseg-bs.mac                                                      ;;
;; ======================================================================== ;;

    LISTING "prev"

	ROM.Setup intybasic_map

	; This macro will 'eat' SRCFILE directives if the assembler doesn't support the directive.
	IF ( DEFINED __FEATURE.SRCFILE ) = 0
	    MACRO SRCFILE x, y
	    ; macro must be non-empty, but a comment works fine.
	    ENDM
	ENDI

CLRSCR:	MVII #$200,R4		; Used also for CLS
	MVO R4,_screen		; Set up starting screen position for PRINT
	MVII #$F0,R1
FILLZERO:
	CLRR R0
MEMSET:
	SARC R1,2
	BNOV $+4
	MVO@ R0,R4
	MVO@ R0,R4
	BNC $+3
	MVO@ R0,R4
	BEQ $+7
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	DECR R1
	BNE $-5
	JR R5

	;
	; Title, Intellivision EXEC will jump over it and start
	; execution directly in _MAIN
	;
	; Note mark is for automatic replacement by IntyBASIC
_TITLE:
	BYTE 125,'pirtoIIDuo',0
        
	;
	; Main program
	;
_MAIN:
	DIS			; Disable interrupts
	MVII #STACK,R6

	;
	; Clean memory
	;
	CALL CLRSCR		; Clean up screen, right here to avoid brief
				; screen display of title in Sears Intellivision.
	MVII #$00e,R1		; 14 of sound (ECS)
	MVII #$0f0,R4		; ECS PSG
	CALL FILLZERO
	MVII #$0fe,R1		; 240 words of 8 bits plus 14 of sound
	MVII #$100,R4		; 8-bit scratch RAM
	CALL FILLZERO

	; Seed random generator using 16 bit RAM (not cleared by EXEC)
	CLRR R0
	MVII #$02F0,R4
	MVII #$0110/4,R1	; Includes phantom memory for extra randomness
_MAIN4:				; This loop is courtesy of GroovyBee
	ADD@ R4,R0
	ADD@ R4,R0
	ADD@ R4,R0
	ADD@ R4,R0
	DECR R1
	BNE _MAIN4
	MVO R0,_rand

	MVII #$058,R1		; 88 words of 16 bits
	MVII #$308,R4		; 16-bit scratch RAM
	CALL FILLZERO

    IF intybasic_jlp
	MVII #$1F40,R1		; Words of 16 bits
	MVII #$8040,R4		; 16-bit scratch RAM
	CALL FILLZERO
    ENDI
    IF intybasic_cc3
	MVII #$1F40,R1		; Words of 16 bits
	MVII #intybasic_cc3*256+$40,R4	; 16-bit scratch RAM
	CALL FILLZERO
    ENDI

	; PAL/NTSC detect
	CALL _set_isr
	DECLE _pal1
	EIS
	DECR PC			; This is a kind of HALT instruction

	; First interrupt may come at a weird time on Tutorvision, or
	; if other startup timing changes.
_pal1:	SUBI #8,R6		; Drop interrupt stack.
	CALL _set_isr
	DECLE _pal2
	DECR PC

	; Second interrupt is safe for initializing MOBs.
	; We will know the screen is off after this one fires.
_pal2:	SUBI #8,R6		; Drop interrupt stack.
	CALL _set_isr
	DECLE _pal3
	; clear MOBs
	CLRR R0
	CLRR R4
	MVII #$18,R2
_pal2_lp:
	MVO@ R0,R4
	DECR R2
	BNE _pal2_lp
	MVO R0,$30		; Reset horizontal delay register
	MVO R0,$31		; Reset vertical delay register

	MVII #-1100,R2		; PAL/NTSC threshold
_pal2_cnt:
	INCR R2
	B _pal2_cnt

	; The final count in R2 will either be negative or positive.
	; If R2 is still -ve, NTSC; else PAL.
_pal3:	SUBI #8,R6		; Drop interrupt stack.
	RLC R2,1
	RLC R2,1
	ANDI #1,R2		; 1 = NTSC, 0 = PAL

	MVII #$55,R1
	MVO R1,$4040
	MVII #$AA,R1
	MVO R1,$4041
	MVI $4040,R1
	CMPI #$55,R1
	BNE _ecs1
	MVI $4041,R1
	CMPI #$AA,R1
	BNE _ecs1
	ADDI #2,R2		; ECS detected flag
_ecs1:
	MVO R2,_ntsc

	CALL _set_isr
	DECLE _int_vector

	CALL CLRSCR		; Because _screen was reset to zero
	CALL _wait
	CALL _init_music
	MVII #2,R0		; Color Stack mode
	MVO R0,_mode_select
	MVII #$038,R0
	MVO R0,$01F8		; Configures sound
	MVO R0,$00F8		; Configures sound (ECS)
	CALL IV_INIT_and_wait	; Setup Intellivoice

;* ======================================================================== *;
;*  These routines are placed into the public domain by their author.  All  *;
;*  copyright rights are hereby relinquished on the routines and data in    *;
;*  this file.  -- James Pujals (DZ-Jay), 2014                              *;
;* ======================================================================== *;

; Modified by Oscar Toledo G. (nanochess), Aug/06/2015
; * Tested all multiplications with automated test.
; * Accelerated multiplication by 7,14,15,28,31,60,62,63,112,120,124
; * Solved bug in multiplication by 23,39,46,47,55,71,78,79,87,92,93,94,95,103,110,111,119
; * Improved sequence of instructions to be more interruptible.

;; ======================================================================== ;;
;;  MULT reg, tmp, const                                                    ;;
;;  Multiplies "reg" by constant "const" and using "tmp" for temporary      ;;
;;  calculations.  The result is placed in "reg."  The multiplication is    ;;
;;  performed by an optimal combination of shifts, additions, and           ;;
;;  subtractions.                                                           ;;
;;                                                                          ;;
;;  NOTE:   The resulting contents of the "tmp" are undefined.              ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      reg         A register containing the multiplicand.                 ;;
;;      tmp         A register for temporary calculations.                  ;;
;;      const       The constant multiplier.                                ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      reg         Output value.                                           ;;
;;      tmp         Trashed.                                                ;;
;;      .ERR.Failed True if operation failed.                               ;;
;; ======================================================================== ;;
MACRO   MULT reg, tmp, const
;
    LISTING "code"

_mul.const      QSET    %const%
_mul.done       QSET    0

        IF (%const% > $7F)
_mul.const      QSET    (_mul.const SHR 1)
                SLL     %reg%,  1
        ENDI

        ; Multiply by $00 (0)
        IF (_mul.const = $00)
_mul.done       QSET    -1
                CLRR    %reg%
        ENDI

        ; Multiply by $01 (1)
        IF (_mul.const = $01)
_mul.done       QSET    -1
                ; Nothing to do
        ENDI

        ; Multiply by $02 (2)
        IF (_mul.const = $02)
_mul.done       QSET    -1
                SLL     %reg%,  1
        ENDI

        ; Multiply by $03 (3)
        IF (_mul.const = $03)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $04 (4)
        IF (_mul.const = $04)
_mul.done       QSET    -1
                SLL     %reg%,  2
        ENDI

        ; Multiply by $05 (5)
        IF (_mul.const = $05)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $06 (6)
        IF (_mul.const = $06)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $07 (7)
        IF (_mul.const = $07)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $08 (8)
        IF (_mul.const = $08)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
        ENDI

        ; Multiply by $09 (9)
        IF (_mul.const = $09)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0A (10)
        IF (_mul.const = $0A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0B (11)
        IF (_mul.const = $0B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0C (12)
        IF (_mul.const = $0C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0D (13)
        IF (_mul.const = $0D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0E (14)
        IF (_mul.const = $0E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0F (15)
        IF (_mul.const = $0F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $10 (16)
        IF (_mul.const = $10)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
        ENDI

        ; Multiply by $11 (17)
        IF (_mul.const = $11)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $12 (18)
        IF (_mul.const = $12)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $13 (19)
        IF (_mul.const = $13)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $14 (20)
        IF (_mul.const = $14)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $15 (21)
        IF (_mul.const = $15)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $16 (22)
        IF (_mul.const = $16)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $17 (23)
        IF (_mul.const = $17)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $18 (24)
        IF (_mul.const = $18)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $19 (25)
        IF (_mul.const = $19)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1A (26)
        IF (_mul.const = $1A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1B (27)
        IF (_mul.const = $1B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1C (28)
        IF (_mul.const = $1C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1D (29)
        IF (_mul.const = $1D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1E (30)
        IF (_mul.const = $1E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1F (31)
        IF (_mul.const = $1F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $20 (32)
        IF (_mul.const = $20)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
        ENDI

        ; Multiply by $21 (33)
        IF (_mul.const = $21)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $22 (34)
        IF (_mul.const = $22)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $23 (35)
        IF (_mul.const = $23)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $24 (36)
        IF (_mul.const = $24)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $25 (37)
        IF (_mul.const = $25)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $26 (38)
        IF (_mul.const = $26)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $27 (39)
        IF (_mul.const = $27)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $28 (40)
        IF (_mul.const = $28)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $29 (41)
        IF (_mul.const = $29)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2A (42)
        IF (_mul.const = $2A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2B (43)
        IF (_mul.const = $2B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2C (44)
        IF (_mul.const = $2C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2D (45)
        IF (_mul.const = $2D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2E (46)
        IF (_mul.const = $2E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,  %reg%
        ENDI

        ; Multiply by $2F (47)
        IF (_mul.const = $2F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,  %reg%
        ENDI

        ; Multiply by $30 (48)
        IF (_mul.const = $30)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $31 (49)
        IF (_mul.const = $31)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $32 (50)
        IF (_mul.const = $32)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $33 (51)
        IF (_mul.const = $33)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $34 (52)
        IF (_mul.const = $34)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $35 (53)
        IF (_mul.const = $35)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $36 (54)
        IF (_mul.const = $36)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $37 (55)
        IF (_mul.const = $37)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
		SLL	%reg%,	1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $38 (56)
        IF (_mul.const = $38)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $39 (57)
        IF (_mul.const = $39)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3A (58)
        IF (_mul.const = $3A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3B (59)
        IF (_mul.const = $3B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3C (60)
        IF (_mul.const = $3C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3D (61)
        IF (_mul.const = $3D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3E (62)
        IF (_mul.const = $3E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3F (63)
        IF (_mul.const = $3F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $40 (64)
        IF (_mul.const = $40)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
        ENDI

        ; Multiply by $41 (65)
        IF (_mul.const = $41)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $42 (66)
        IF (_mul.const = $42)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $43 (67)
        IF (_mul.const = $43)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $44 (68)
        IF (_mul.const = $44)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $45 (69)
        IF (_mul.const = $45)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $46 (70)
        IF (_mul.const = $46)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $47 (71)
        IF (_mul.const = $47)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $48 (72)
        IF (_mul.const = $48)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $49 (73)
        IF (_mul.const = $49)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4A (74)
        IF (_mul.const = $4A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4B (75)
        IF (_mul.const = $4B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4C (76)
        IF (_mul.const = $4C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4D (77)
        IF (_mul.const = $4D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4E (78)
        IF (_mul.const = $4E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $4F (79)
        IF (_mul.const = $4F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $50 (80)
        IF (_mul.const = $50)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $51 (81)
        IF (_mul.const = $51)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $52 (82)
        IF (_mul.const = $52)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $53 (83)
        IF (_mul.const = $53)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $54 (84)
        IF (_mul.const = $54)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $55 (85)
        IF (_mul.const = $55)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $56 (86)
        IF (_mul.const = $56)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $57 (87)
        IF (_mul.const = $57)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR    %reg%,	%tmp%
                SLL     %reg%,  2
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $58 (88)
        IF (_mul.const = $58)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $59 (89)
        IF (_mul.const = $59)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $5A (90)
        IF (_mul.const = $5A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $5B (91)
        IF (_mul.const = $5B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $5C (92)
        IF (_mul.const = $5C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $5D (93)
        IF (_mul.const = $5D)
_mul.done       QSET    -1
		MOVR	%reg%,	%tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $5E (94)
        IF (_mul.const = $5E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $5F (95)
        IF (_mul.const = $5F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                ADDR	%reg%,	%reg%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $60 (96)
        IF (_mul.const = $60)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $61 (97)
        IF (_mul.const = $61)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $62 (98)
        IF (_mul.const = $62)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $63 (99)
        IF (_mul.const = $63)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $64 (100)
        IF (_mul.const = $64)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $65 (101)
        IF (_mul.const = $65)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $66 (102)
        IF (_mul.const = $66)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $67 (103)
        IF (_mul.const = $67)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $68 (104)
        IF (_mul.const = $68)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $69 (105)
        IF (_mul.const = $69)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6A (106)
        IF (_mul.const = $6A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6B (107)
        IF (_mul.const = $6B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6C (108)
        IF (_mul.const = $6C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6D (109)
        IF (_mul.const = $6D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6E (110)
        IF (_mul.const = $6E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $6F (111)
        IF (_mul.const = $6F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $70 (112)
        IF (_mul.const = $70)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $71 (113)
        IF (_mul.const = $71)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $72 (114)
        IF (_mul.const = $72)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $73 (115)
        IF (_mul.const = $73)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $74 (116)
        IF (_mul.const = $74)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $75 (117)
        IF (_mul.const = $75)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $76 (118)
        IF (_mul.const = $76)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $77 (119)
        IF (_mul.const = $77)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $78 (120)
        IF (_mul.const = $78)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $79 (121)
        IF (_mul.const = $79)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7A (122)
        IF (_mul.const = $7A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7B (123)
        IF (_mul.const = $7B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7C (124)
        IF (_mul.const = $7C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7D (125)
        IF (_mul.const = $7D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7E (126)
        IF (_mul.const = $7E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7F (127)
        IF (_mul.const = $7F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        IF  (_mul.done = 0)
            ERR $("Invalid multiplication constant \'%const%\', must be between 0 and ", $#($7F), ".")
        ENDI

    LISTING "prev"
ENDM

;; ======================================================================== ;;
;;  EOF: pm:mac:lang:mult                                                   ;;
;; ======================================================================== ;;

	; IntyBASIC compiler v1.5.1 May/10/2025
	;FILE pirtoIIDuo.bas
	;[1]     REM IntyColor v1.1.7 Dec/03/2018
	SRCFILE "pirtoIIDuo.bas",1
	;[2]     REM Command: intycolor -b pirto_s.bmp pirto.bas 
	SRCFILE "pirtoIIDuo.bas",2
	;[3]     REM Created: Fri Jan 19 11:47:51 2024
	SRCFILE "pirtoIIDuo.bas",3
	;[4] 
	SRCFILE "pirtoIIDuo.bas",4
	;[5]     REM stub for showing image
	SRCFILE "pirtoIIDuo.bas",5
	;[6] 
	SRCFILE "pirtoIIDuo.bas",6
	;[7]     ASM MEMATTR $8000, $9fFF, "+RWN"
	SRCFILE "pirtoIIDuo.bas",7
 MEMATTR $8000, $9fFF, "+RWN"
	;[8] 
	SRCFILE "pirtoIIDuo.bas",8
	;[9]     ' We need some important constants.
	SRCFILE "pirtoIIDuo.bas",9
	;[10]     INCLUDE "constants.bas"
	SRCFILE "pirtoIIDuo.bas",10
	;FILE constants.bas
	;[1] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",1
	;[2] REM HEADER - CONSTANTS.BAS
	SRCFILE "constants.bas",2
	;[3] REM
	SRCFILE "constants.bas",3
	;[4] REM Started by Mark Ball, July 2015
	SRCFILE "constants.bas",4
	;[5] REM
	SRCFILE "constants.bas",5
	;[6] REM Constants for use in IntyBASIC
	SRCFILE "constants.bas",6
	;[7] REM
	SRCFILE "constants.bas",7
	;[8] REM HISTORY
	SRCFILE "constants.bas",8
	;[9] REM -------
	SRCFILE "constants.bas",9
	;[10] REM 1.00F 05/07/15 - First version.
	SRCFILE "constants.bas",10
	;[11] REM 1.01F 07/07/15 - Added disc directions.
	SRCFILE "constants.bas",11
	;[12] REM                - Added background modes.
	SRCFILE "constants.bas",12
	;[13] REM                - Minor comment changes.
	SRCFILE "constants.bas",13
	;[14] REM 1.02F 08/07/15 - Renamed constants.
	SRCFILE "constants.bas",14
	;[15] REM                - Added background access information.
	SRCFILE "constants.bas",15
	;[16] REM                - Adjustments to layout.
	SRCFILE "constants.bas",16
	;[17] REM 1.03F 08/07/15 - Fixed comment delimiter.
	SRCFILE "constants.bas",17
	;[18] REM 1.04F 11/07/15 - Added useful functions.
	SRCFILE "constants.bas",18
	;[19] REM                - Added controller movement mask.
	SRCFILE "constants.bas",19
	;[20] REM 1.05F 11/07/15 - Added BACKGROUND constants.
	SRCFILE "constants.bas",20
	;[21] REM 1.06F 11/07/15 - Changed Y, X order to X, Y in DEF FN functions.
	SRCFILE "constants.bas",21
	;[22] REM 1.07F 11/07/15 - Added colour stack advance.
	SRCFILE "constants.bas",22
	;[23] REM 1.08F 12/07/15 - Added functions for sprite position handling.
	SRCFILE "constants.bas",23
	;[24] REM 1.09F 12/07/15 - Added a function for resetting a sprite.
	SRCFILE "constants.bas",24
	;[25] REM 1.10F 13/07/15 - Added keypad constants.
	SRCFILE "constants.bas",25
	;[26] REM 1.11F 13/07/15 - Added side button constants.
	SRCFILE "constants.bas",26
	;[27] REM 1.12F 13/07/15 - Updated sprite functions.
	SRCFILE "constants.bas",27
	;[28] REM 1.13F 19/07/15 - Added border masking constants.
	SRCFILE "constants.bas",28
	;[29] REM 1.14F 20/07/15 - Added a combined border masking constant.
	SRCFILE "constants.bas",29
	;[30] REM 1.15F 20/07/15 - Renamed border masking constants to BORDER_HIDE_xxxx.
	SRCFILE "constants.bas",30
	;[31] REM 1.16F 28/09/15 - Fixed disc direction typos.
	SRCFILE "constants.bas",31
	;[32] REM 1.17F 30/09/15 - Fixed DISC_SOUTH_WEST value.
	SRCFILE "constants.bas",32
	;[33] REM 1.18F 05/12/15 - Fixed BG_XXXX colours.
	SRCFILE "constants.bas",33
	;[34] REM 1.19F 01/01/16 - Changed name of BACKTAB constant to avoid confusion with #BACKTAB array.
	SRCFILE "constants.bas",34
	;[35] REM                - Added pause key constants.
	SRCFILE "constants.bas",35
	;[36] REM 1.20F 14/01/16 - Added coloured squares mode's pixel colours.
	SRCFILE "constants.bas",36
	;[37] REM 1.21F 15/01/16 - Added coloured squares mode's X and Y limits.
	SRCFILE "constants.bas",37
	;[38] REM 1.22F 23/01/16 - Added PSG constants.
	SRCFILE "constants.bas",38
	;[39] REM 1.23F 24/01/16 - Fixed typo in PSG comments.
	SRCFILE "constants.bas",39
	;[40] REM 1.24F 16/11/16 - Added toggle DEF FN's for sprite's BEHIND, HIT and VISIBLE.
	SRCFILE "constants.bas",40
	;[41] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",41
	;[42] 
	SRCFILE "constants.bas",42
	;[43] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",43
	;[44] 
	SRCFILE "constants.bas",44
	;[45] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",45
	;[46] REM Background information.
	SRCFILE "constants.bas",46
	;[47] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",47
	;[48] CONST BACKTAB_ADDR					= $0200		' Start of the BACKground TABle (BACKTAB) in RAM.
	SRCFILE "constants.bas",48
const_BACKTAB_ADDR:	EQU 512
	;[49] CONST BACKGROUND_ROWS				= 12		' Height of the background in cards.
	SRCFILE "constants.bas",49
const_BACKGROUND_ROWS:	EQU 12
	;[50] CONST BACKGROUND_COLUMNS			= 20		' Width of the background in cards.
	SRCFILE "constants.bas",50
const_BACKGROUND_COLUMNS:	EQU 20
	;[51] 
	SRCFILE "constants.bas",51
	;[52] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",52
	;[53] REM Background GRAM cards.
	SRCFILE "constants.bas",53
	;[54] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",54
	;[55] CONST BG00							= $0800
	SRCFILE "constants.bas",55
const_BG00:	EQU 2048
	;[56] CONST BG01							= $0808
	SRCFILE "constants.bas",56
const_BG01:	EQU 2056
	;[57] CONST BG02							= $0810
	SRCFILE "constants.bas",57
const_BG02:	EQU 2064
	;[58] CONST BG03							= $0818
	SRCFILE "constants.bas",58
const_BG03:	EQU 2072
	;[59] CONST BG04							= $0820
	SRCFILE "constants.bas",59
const_BG04:	EQU 2080
	;[60] CONST BG05							= $0828
	SRCFILE "constants.bas",60
const_BG05:	EQU 2088
	;[61] CONST BG06							= $0830
	SRCFILE "constants.bas",61
const_BG06:	EQU 2096
	;[62] CONST BG07							= $0838
	SRCFILE "constants.bas",62
const_BG07:	EQU 2104
	;[63] CONST BG08							= $0840
	SRCFILE "constants.bas",63
const_BG08:	EQU 2112
	;[64] CONST BG09							= $0848
	SRCFILE "constants.bas",64
const_BG09:	EQU 2120
	;[65] CONST BG10							= $0850
	SRCFILE "constants.bas",65
const_BG10:	EQU 2128
	;[66] CONST BG11							= $0858
	SRCFILE "constants.bas",66
const_BG11:	EQU 2136
	;[67] CONST BG12							= $0860
	SRCFILE "constants.bas",67
const_BG12:	EQU 2144
	;[68] CONST BG13							= $0868
	SRCFILE "constants.bas",68
const_BG13:	EQU 2152
	;[69] CONST BG14							= $0870
	SRCFILE "constants.bas",69
const_BG14:	EQU 2160
	;[70] CONST BG15							= $0878
	SRCFILE "constants.bas",70
const_BG15:	EQU 2168
	;[71] CONST BG16							= $0880
	SRCFILE "constants.bas",71
const_BG16:	EQU 2176
	;[72] CONST BG17							= $0888
	SRCFILE "constants.bas",72
const_BG17:	EQU 2184
	;[73] CONST BG18							= $0890
	SRCFILE "constants.bas",73
const_BG18:	EQU 2192
	;[74] CONST BG19							= $0898
	SRCFILE "constants.bas",74
const_BG19:	EQU 2200
	;[75] CONST BG20							= $08A0
	SRCFILE "constants.bas",75
const_BG20:	EQU 2208
	;[76] CONST BG21							= $08A8
	SRCFILE "constants.bas",76
const_BG21:	EQU 2216
	;[77] CONST BG22							= $08B0
	SRCFILE "constants.bas",77
const_BG22:	EQU 2224
	;[78] CONST BG23							= $08B8
	SRCFILE "constants.bas",78
const_BG23:	EQU 2232
	;[79] CONST BG24							= $08C0
	SRCFILE "constants.bas",79
const_BG24:	EQU 2240
	;[80] CONST BG25							= $08C8
	SRCFILE "constants.bas",80
const_BG25:	EQU 2248
	;[81] CONST BG26							= $08D0
	SRCFILE "constants.bas",81
const_BG26:	EQU 2256
	;[82] CONST BG27							= $08D8
	SRCFILE "constants.bas",82
const_BG27:	EQU 2264
	;[83] CONST BG28							= $08E0
	SRCFILE "constants.bas",83
const_BG28:	EQU 2272
	;[84] CONST BG29							= $08E8
	SRCFILE "constants.bas",84
const_BG29:	EQU 2280
	;[85] CONST BG30							= $08F0
	SRCFILE "constants.bas",85
const_BG30:	EQU 2288
	;[86] CONST BG31							= $08F8
	SRCFILE "constants.bas",86
const_BG31:	EQU 2296
	;[87] CONST BG32							= $0900
	SRCFILE "constants.bas",87
const_BG32:	EQU 2304
	;[88] CONST BG33							= $0908
	SRCFILE "constants.bas",88
const_BG33:	EQU 2312
	;[89] CONST BG34							= $0910
	SRCFILE "constants.bas",89
const_BG34:	EQU 2320
	;[90] CONST BG35							= $0918
	SRCFILE "constants.bas",90
const_BG35:	EQU 2328
	;[91] CONST BG36							= $0920
	SRCFILE "constants.bas",91
const_BG36:	EQU 2336
	;[92] CONST BG37							= $0928
	SRCFILE "constants.bas",92
const_BG37:	EQU 2344
	;[93] CONST BG38							= $0930
	SRCFILE "constants.bas",93
const_BG38:	EQU 2352
	;[94] CONST BG39							= $0938
	SRCFILE "constants.bas",94
const_BG39:	EQU 2360
	;[95] CONST BG40							= $0940
	SRCFILE "constants.bas",95
const_BG40:	EQU 2368
	;[96] CONST BG41							= $0948
	SRCFILE "constants.bas",96
const_BG41:	EQU 2376
	;[97] CONST BG42							= $0950
	SRCFILE "constants.bas",97
const_BG42:	EQU 2384
	;[98] CONST BG43							= $0958
	SRCFILE "constants.bas",98
const_BG43:	EQU 2392
	;[99] CONST BG44							= $0960
	SRCFILE "constants.bas",99
const_BG44:	EQU 2400
	;[100] CONST BG45							= $0968
	SRCFILE "constants.bas",100
const_BG45:	EQU 2408
	;[101] CONST BG46							= $0970
	SRCFILE "constants.bas",101
const_BG46:	EQU 2416
	;[102] CONST BG47							= $0978
	SRCFILE "constants.bas",102
const_BG47:	EQU 2424
	;[103] CONST BG48							= $0980
	SRCFILE "constants.bas",103
const_BG48:	EQU 2432
	;[104] CONST BG49							= $0988
	SRCFILE "constants.bas",104
const_BG49:	EQU 2440
	;[105] CONST BG50							= $0990
	SRCFILE "constants.bas",105
const_BG50:	EQU 2448
	;[106] CONST BG51							= $0998
	SRCFILE "constants.bas",106
const_BG51:	EQU 2456
	;[107] CONST BG52							= $09A0
	SRCFILE "constants.bas",107
const_BG52:	EQU 2464
	;[108] CONST BG53							= $09A8
	SRCFILE "constants.bas",108
const_BG53:	EQU 2472
	;[109] CONST BG54							= $09B0
	SRCFILE "constants.bas",109
const_BG54:	EQU 2480
	;[110] CONST BG55							= $09B8
	SRCFILE "constants.bas",110
const_BG55:	EQU 2488
	;[111] CONST BG56							= $09C0
	SRCFILE "constants.bas",111
const_BG56:	EQU 2496
	;[112] CONST BG57							= $09C8
	SRCFILE "constants.bas",112
const_BG57:	EQU 2504
	;[113] CONST BG58							= $09D0
	SRCFILE "constants.bas",113
const_BG58:	EQU 2512
	;[114] CONST BG59							= $09D8
	SRCFILE "constants.bas",114
const_BG59:	EQU 2520
	;[115] CONST BG60							= $09E0
	SRCFILE "constants.bas",115
const_BG60:	EQU 2528
	;[116] CONST BG61							= $09E8
	SRCFILE "constants.bas",116
const_BG61:	EQU 2536
	;[117] CONST BG62							= $09F0
	SRCFILE "constants.bas",117
const_BG62:	EQU 2544
	;[118] CONST BG63							= $09F8
	SRCFILE "constants.bas",118
const_BG63:	EQU 2552
	;[119] 
	SRCFILE "constants.bas",119
	;[120] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",120
	;[121] 
	SRCFILE "constants.bas",121
	;[122] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",122
	;[123] REM GRAM card index numbers.
	SRCFILE "constants.bas",123
	;[124] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",124
	;[125] REM Note: For use with the "define" command.
	SRCFILE "constants.bas",125
	;[126] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",126
	;[127] CONST DEF00							= $0000
	SRCFILE "constants.bas",127
const_DEF00:	EQU 0
	;[128] CONST DEF01							= $0001
	SRCFILE "constants.bas",128
const_DEF01:	EQU 1
	;[129] CONST DEF02							= $0002
	SRCFILE "constants.bas",129
const_DEF02:	EQU 2
	;[130] CONST DEF03							= $0003
	SRCFILE "constants.bas",130
const_DEF03:	EQU 3
	;[131] CONST DEF04							= $0004
	SRCFILE "constants.bas",131
const_DEF04:	EQU 4
	;[132] CONST DEF05							= $0005
	SRCFILE "constants.bas",132
const_DEF05:	EQU 5
	;[133] CONST DEF06							= $0006
	SRCFILE "constants.bas",133
const_DEF06:	EQU 6
	;[134] CONST DEF07							= $0007
	SRCFILE "constants.bas",134
const_DEF07:	EQU 7
	;[135] CONST DEF08							= $0008
	SRCFILE "constants.bas",135
const_DEF08:	EQU 8
	;[136] CONST DEF09							= $0009
	SRCFILE "constants.bas",136
const_DEF09:	EQU 9
	;[137] CONST DEF10							= $000A
	SRCFILE "constants.bas",137
const_DEF10:	EQU 10
	;[138] CONST DEF11							= $000B
	SRCFILE "constants.bas",138
const_DEF11:	EQU 11
	;[139] CONST DEF12							= $000C
	SRCFILE "constants.bas",139
const_DEF12:	EQU 12
	;[140] CONST DEF13							= $000D
	SRCFILE "constants.bas",140
const_DEF13:	EQU 13
	;[141] CONST DEF14							= $000E
	SRCFILE "constants.bas",141
const_DEF14:	EQU 14
	;[142] CONST DEF15							= $000F
	SRCFILE "constants.bas",142
const_DEF15:	EQU 15
	;[143] CONST DEF16							= $0010
	SRCFILE "constants.bas",143
const_DEF16:	EQU 16
	;[144] CONST DEF17							= $0011
	SRCFILE "constants.bas",144
const_DEF17:	EQU 17
	;[145] CONST DEF18							= $0012
	SRCFILE "constants.bas",145
const_DEF18:	EQU 18
	;[146] CONST DEF19							= $0013
	SRCFILE "constants.bas",146
const_DEF19:	EQU 19
	;[147] CONST DEF20							= $0014
	SRCFILE "constants.bas",147
const_DEF20:	EQU 20
	;[148] CONST DEF21							= $0015
	SRCFILE "constants.bas",148
const_DEF21:	EQU 21
	;[149] CONST DEF22							= $0016
	SRCFILE "constants.bas",149
const_DEF22:	EQU 22
	;[150] CONST DEF23							= $0017
	SRCFILE "constants.bas",150
const_DEF23:	EQU 23
	;[151] CONST DEF24							= $0018
	SRCFILE "constants.bas",151
const_DEF24:	EQU 24
	;[152] CONST DEF25							= $0019
	SRCFILE "constants.bas",152
const_DEF25:	EQU 25
	;[153] CONST DEF26							= $001A
	SRCFILE "constants.bas",153
const_DEF26:	EQU 26
	;[154] CONST DEF27							= $001B
	SRCFILE "constants.bas",154
const_DEF27:	EQU 27
	;[155] CONST DEF28							= $001C
	SRCFILE "constants.bas",155
const_DEF28:	EQU 28
	;[156] CONST DEF29							= $001D
	SRCFILE "constants.bas",156
const_DEF29:	EQU 29
	;[157] CONST DEF30							= $001E
	SRCFILE "constants.bas",157
const_DEF30:	EQU 30
	;[158] CONST DEF31							= $001F
	SRCFILE "constants.bas",158
const_DEF31:	EQU 31
	;[159] CONST DEF32							= $0020
	SRCFILE "constants.bas",159
const_DEF32:	EQU 32
	;[160] CONST DEF33							= $0021
	SRCFILE "constants.bas",160
const_DEF33:	EQU 33
	;[161] CONST DEF34							= $0022
	SRCFILE "constants.bas",161
const_DEF34:	EQU 34
	;[162] CONST DEF35							= $0023
	SRCFILE "constants.bas",162
const_DEF35:	EQU 35
	;[163] CONST DEF36							= $0024
	SRCFILE "constants.bas",163
const_DEF36:	EQU 36
	;[164] CONST DEF37							= $0025
	SRCFILE "constants.bas",164
const_DEF37:	EQU 37
	;[165] CONST DEF38							= $0026
	SRCFILE "constants.bas",165
const_DEF38:	EQU 38
	;[166] CONST DEF39							= $0027
	SRCFILE "constants.bas",166
const_DEF39:	EQU 39
	;[167] CONST DEF40							= $0028
	SRCFILE "constants.bas",167
const_DEF40:	EQU 40
	;[168] CONST DEF41							= $0029
	SRCFILE "constants.bas",168
const_DEF41:	EQU 41
	;[169] CONST DEF42							= $002A
	SRCFILE "constants.bas",169
const_DEF42:	EQU 42
	;[170] CONST DEF43							= $002B
	SRCFILE "constants.bas",170
const_DEF43:	EQU 43
	;[171] CONST DEF44							= $002C
	SRCFILE "constants.bas",171
const_DEF44:	EQU 44
	;[172] CONST DEF45							= $002D
	SRCFILE "constants.bas",172
const_DEF45:	EQU 45
	;[173] CONST DEF46							= $002E
	SRCFILE "constants.bas",173
const_DEF46:	EQU 46
	;[174] CONST DEF47							= $002F
	SRCFILE "constants.bas",174
const_DEF47:	EQU 47
	;[175] CONST DEF48							= $0030
	SRCFILE "constants.bas",175
const_DEF48:	EQU 48
	;[176] CONST DEF49							= $0031
	SRCFILE "constants.bas",176
const_DEF49:	EQU 49
	;[177] CONST DEF50							= $0032
	SRCFILE "constants.bas",177
const_DEF50:	EQU 50
	;[178] CONST DEF51							= $0033
	SRCFILE "constants.bas",178
const_DEF51:	EQU 51
	;[179] CONST DEF52							= $0034
	SRCFILE "constants.bas",179
const_DEF52:	EQU 52
	;[180] CONST DEF53							= $0035
	SRCFILE "constants.bas",180
const_DEF53:	EQU 53
	;[181] CONST DEF54							= $0036
	SRCFILE "constants.bas",181
const_DEF54:	EQU 54
	;[182] CONST DEF55							= $0037
	SRCFILE "constants.bas",182
const_DEF55:	EQU 55
	;[183] CONST DEF56							= $0038
	SRCFILE "constants.bas",183
const_DEF56:	EQU 56
	;[184] CONST DEF57							= $0039
	SRCFILE "constants.bas",184
const_DEF57:	EQU 57
	;[185] CONST DEF58							= $003A
	SRCFILE "constants.bas",185
const_DEF58:	EQU 58
	;[186] CONST DEF59							= $003B
	SRCFILE "constants.bas",186
const_DEF59:	EQU 59
	;[187] CONST DEF60							= $003C
	SRCFILE "constants.bas",187
const_DEF60:	EQU 60
	;[188] CONST DEF61							= $003D
	SRCFILE "constants.bas",188
const_DEF61:	EQU 61
	;[189] CONST DEF62							= $003E
	SRCFILE "constants.bas",189
const_DEF62:	EQU 62
	;[190] CONST DEF63							= $003F
	SRCFILE "constants.bas",190
const_DEF63:	EQU 63
	;[191] 
	SRCFILE "constants.bas",191
	;[192] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",192
	;[193] 
	SRCFILE "constants.bas",193
	;[194] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",194
	;[195] REM Screen modes.
	SRCFILE "constants.bas",195
	;[196] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",196
	;[197] REM Note: For use with the "mode" command.
	SRCFILE "constants.bas",197
	;[198] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",198
	;[199] CONST SCREEN_COLOR_STACK			= $0000
	SRCFILE "constants.bas",199
const_SCREEN_COLOR_STACK:	EQU 0
	;[200] CONST SCREEN_FOREGROUND_BACKGROUND	= $0001
	SRCFILE "constants.bas",200
const_SCREEN_FOREGROUND_BACKGROUND:	EQU 1
	;[201] REM Abbreviated versions.
	SRCFILE "constants.bas",201
	;[202] CONST SCREEN_CS						= $0000
	SRCFILE "constants.bas",202
const_SCREEN_CS:	EQU 0
	;[203] CONST SCREEN_FB						= $0001
	SRCFILE "constants.bas",203
const_SCREEN_FB:	EQU 1
	;[204] 
	SRCFILE "constants.bas",204
	;[205] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",205
	;[206] 
	SRCFILE "constants.bas",206
	;[207] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",207
	;[208] REM COLORS - Border.
	SRCFILE "constants.bas",208
	;[209] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",209
	;[210] REM Notes:
	SRCFILE "constants.bas",210
	;[211] REM - For use with the commands "mode 0" and "mode 1".
	SRCFILE "constants.bas",211
	;[212] REM - For use with the "border" command.
	SRCFILE "constants.bas",212
	;[213] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",213
	;[214] CONST BORDER_BLACK					= $0000
	SRCFILE "constants.bas",214
const_BORDER_BLACK:	EQU 0
	;[215] CONST BORDER_BLUE					= $0001
	SRCFILE "constants.bas",215
const_BORDER_BLUE:	EQU 1
	;[216] CONST BORDER_RED					= $0002
	SRCFILE "constants.bas",216
const_BORDER_RED:	EQU 2
	;[217] CONST BORDER_TAN					= $0003
	SRCFILE "constants.bas",217
const_BORDER_TAN:	EQU 3
	;[218] CONST BORDER_DARKGREEN				= $0004
	SRCFILE "constants.bas",218
const_BORDER_DARKGREEN:	EQU 4
	;[219] CONST BORDER_GREEN					= $0005
	SRCFILE "constants.bas",219
const_BORDER_GREEN:	EQU 5
	;[220] CONST BORDER_YELLOW					= $0006
	SRCFILE "constants.bas",220
const_BORDER_YELLOW:	EQU 6
	;[221] CONST BORDER_WHITE					= $0007
	SRCFILE "constants.bas",221
const_BORDER_WHITE:	EQU 7
	;[222] CONST BORDER_GREY					= $0008
	SRCFILE "constants.bas",222
const_BORDER_GREY:	EQU 8
	;[223] CONST BORDER_CYAN					= $0009
	SRCFILE "constants.bas",223
const_BORDER_CYAN:	EQU 9
	;[224] CONST BORDER_ORANGE					= $000A
	SRCFILE "constants.bas",224
const_BORDER_ORANGE:	EQU 10
	;[225] CONST BORDER_BROWN					= $000B
	SRCFILE "constants.bas",225
const_BORDER_BROWN:	EQU 11
	;[226] CONST BORDER_PINK					= $000C
	SRCFILE "constants.bas",226
const_BORDER_PINK:	EQU 12
	;[227] CONST BORDER_LIGHTBLUE				= $000D
	SRCFILE "constants.bas",227
const_BORDER_LIGHTBLUE:	EQU 13
	;[228] CONST BORDER_YELLOWGREEN			= $000E
	SRCFILE "constants.bas",228
const_BORDER_YELLOWGREEN:	EQU 14
	;[229] CONST BORDER_PURPLE					= $000F
	SRCFILE "constants.bas",229
const_BORDER_PURPLE:	EQU 15
	;[230] 
	SRCFILE "constants.bas",230
	;[231] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",231
	;[232] 
	SRCFILE "constants.bas",232
	;[233] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",233
	;[234] REM BORDER - Edge masks.
	SRCFILE "constants.bas",234
	;[235] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",235
	;[236] REM Note: For use with the "border color, edge" command.
	SRCFILE "constants.bas",236
	;[237] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",237
	;[238] CONST BORDER_HIDE_LEFT_EDGE			= $0001		' Hide the leftmost column of the background.
	SRCFILE "constants.bas",238
const_BORDER_HIDE_LEFT_EDGE:	EQU 1
	;[239] CONST BORDER_HIDE_TOP_EDGE			= $0002		' Hide the topmost row of the background.
	SRCFILE "constants.bas",239
const_BORDER_HIDE_TOP_EDGE:	EQU 2
	;[240] CONST BORDER_HIDE_TOP_LEFT_EDGE		= $0003		' Hide both the topmost row and leftmost column of the background.
	SRCFILE "constants.bas",240
const_BORDER_HIDE_TOP_LEFT_EDGE:	EQU 3
	;[241] 
	SRCFILE "constants.bas",241
	;[242] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",242
	;[243] 
	SRCFILE "constants.bas",243
	;[244] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",244
	;[245] REM COLORS - Mode 0 (Color Stack).
	SRCFILE "constants.bas",245
	;[246] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",246
	;[247] REM Stack
	SRCFILE "constants.bas",247
	;[248] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",248
	;[249] REM Note: For use as the last 4 parameters used in the "mode 1" command.
	SRCFILE "constants.bas",249
	;[250] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",250
	;[251] CONST STACK_BLACK					= $0000
	SRCFILE "constants.bas",251
const_STACK_BLACK:	EQU 0
	;[252] CONST STACK_BLUE					= $0001
	SRCFILE "constants.bas",252
const_STACK_BLUE:	EQU 1
	;[253] CONST STACK_RED						= $0002
	SRCFILE "constants.bas",253
const_STACK_RED:	EQU 2
	;[254] CONST STACK_TAN						= $0003
	SRCFILE "constants.bas",254
const_STACK_TAN:	EQU 3
	;[255] CONST STACK_DARKGREEN				= $0004
	SRCFILE "constants.bas",255
const_STACK_DARKGREEN:	EQU 4
	;[256] CONST STACK_GREEN					= $0005
	SRCFILE "constants.bas",256
const_STACK_GREEN:	EQU 5
	;[257] CONST STACK_YELLOW					= $0006
	SRCFILE "constants.bas",257
const_STACK_YELLOW:	EQU 6
	;[258] CONST STACK_WHITE					= $0007
	SRCFILE "constants.bas",258
const_STACK_WHITE:	EQU 7
	;[259] CONST STACK_GREY					= $0008
	SRCFILE "constants.bas",259
const_STACK_GREY:	EQU 8
	;[260] CONST STACK_CYAN					= $0009
	SRCFILE "constants.bas",260
const_STACK_CYAN:	EQU 9
	;[261] CONST STACK_ORANGE					= $000A
	SRCFILE "constants.bas",261
const_STACK_ORANGE:	EQU 10
	;[262] CONST STACK_BROWN					= $000B
	SRCFILE "constants.bas",262
const_STACK_BROWN:	EQU 11
	;[263] CONST STACK_PINK					= $000C
	SRCFILE "constants.bas",263
const_STACK_PINK:	EQU 12
	;[264] CONST STACK_LIGHTBLUE				= $000D
	SRCFILE "constants.bas",264
const_STACK_LIGHTBLUE:	EQU 13
	;[265] CONST STACK_YELLOWGREEN				= $000E
	SRCFILE "constants.bas",265
const_STACK_YELLOWGREEN:	EQU 14
	;[266] CONST STACK_PURPLE					= $000F
	SRCFILE "constants.bas",266
const_STACK_PURPLE:	EQU 15
	;[267] 
	SRCFILE "constants.bas",267
	;[268] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",268
	;[269] REM Foreground.
	SRCFILE "constants.bas",269
	;[270] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",270
	;[271] REM Notes:
	SRCFILE "constants.bas",271
	;[272] REM - For use with "peek/poke" commands that access BACKTAB.
	SRCFILE "constants.bas",272
	;[273] REM - Only one foreground colour permitted per background card.
	SRCFILE "constants.bas",273
	;[274] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",274
	;[275] CONST CS_BLACK						= $0000
	SRCFILE "constants.bas",275
const_CS_BLACK:	EQU 0
	;[276] CONST CS_BLUE						= $0001
	SRCFILE "constants.bas",276
const_CS_BLUE:	EQU 1
	;[277] CONST CS_RED						= $0002
	SRCFILE "constants.bas",277
const_CS_RED:	EQU 2
	;[278] CONST CS_TAN						= $0003
	SRCFILE "constants.bas",278
const_CS_TAN:	EQU 3
	;[279] CONST CS_DARKGREEN					= $0004
	SRCFILE "constants.bas",279
const_CS_DARKGREEN:	EQU 4
	;[280] CONST CS_GREEN						= $0005
	SRCFILE "constants.bas",280
const_CS_GREEN:	EQU 5
	;[281] CONST CS_YELLOW						= $0006
	SRCFILE "constants.bas",281
const_CS_YELLOW:	EQU 6
	;[282] CONST CS_WHITE						= $0007
	SRCFILE "constants.bas",282
const_CS_WHITE:	EQU 7
	;[283] CONST CS_GREY						= $1000
	SRCFILE "constants.bas",283
const_CS_GREY:	EQU 4096
	;[284] CONST CS_CYAN						= $1001
	SRCFILE "constants.bas",284
const_CS_CYAN:	EQU 4097
	;[285] CONST CS_ORANGE						= $1002
	SRCFILE "constants.bas",285
const_CS_ORANGE:	EQU 4098
	;[286] CONST CS_BROWN						= $1003
	SRCFILE "constants.bas",286
const_CS_BROWN:	EQU 4099
	;[287] CONST CS_PINK						= $1004
	SRCFILE "constants.bas",287
const_CS_PINK:	EQU 4100
	;[288] CONST CS_LIGHTBLUE					= $1005
	SRCFILE "constants.bas",288
const_CS_LIGHTBLUE:	EQU 4101
	;[289] CONST CS_YELLOWGREEN				= $1006
	SRCFILE "constants.bas",289
const_CS_YELLOWGREEN:	EQU 4102
	;[290] CONST CS_PURPLE						= $1007
	SRCFILE "constants.bas",290
const_CS_PURPLE:	EQU 4103
	;[291] 
	SRCFILE "constants.bas",291
	;[292] CONST CS_CARD_DATA_MASK				= $07F8		' Mask to get the background card's data.
	SRCFILE "constants.bas",292
const_CS_CARD_DATA_MASK:	EQU 2040
	;[293] 
	SRCFILE "constants.bas",293
	;[294] CONST CS_ADVANCE					= $2000		' Advance the colour stack by one position.
	SRCFILE "constants.bas",294
const_CS_ADVANCE:	EQU 8192
	;[295] 
	SRCFILE "constants.bas",295
	;[296] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",296
	;[297] REM Coloured squares mode.
	SRCFILE "constants.bas",297
	;[298] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",298
	;[299] REM Notes :
	SRCFILE "constants.bas",299
	;[300] REM - Only available in colour stack mode.
	SRCFILE "constants.bas",300
	;[301] REM - Pixels in each BACKTAB card are arranged in the following manner:
	SRCFILE "constants.bas",301
	;[302] REM +-------+-------+
	SRCFILE "constants.bas",302
	;[303] REM | Pixel | Pixel |
	SRCFILE "constants.bas",303
	;[304] REM |   0   |   1   !
	SRCFILE "constants.bas",304
	;[305] REM +-------+-------+
	SRCFILE "constants.bas",305
	;[306] REM | Pixel | Pixel |
	SRCFILE "constants.bas",306
	;[307] REM |   2   |   3   !
	SRCFILE "constants.bas",307
	;[308] REM +-------+-------+
	SRCFILE "constants.bas",308
	;[309] REM
	SRCFILE "constants.bas",309
	;[310] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",310
	;[311] CONST CS_COLOUR_SQUARES_ENABLE		= $1000
	SRCFILE "constants.bas",311
const_CS_COLOUR_SQUARES_ENABLE:	EQU 4096
	;[312] CONST CS_PIX0_BLACK					= 0
	SRCFILE "constants.bas",312
const_CS_PIX0_BLACK:	EQU 0
	;[313] CONST CS_PIX0_BLUE					= 1
	SRCFILE "constants.bas",313
const_CS_PIX0_BLUE:	EQU 1
	;[314] CONST CS_PIX0_RED					= 2
	SRCFILE "constants.bas",314
const_CS_PIX0_RED:	EQU 2
	;[315] CONST CS_PIX0_TAN					= 3
	SRCFILE "constants.bas",315
const_CS_PIX0_TAN:	EQU 3
	;[316] CONST CS_PIX0_DARKGREEN				= 4
	SRCFILE "constants.bas",316
const_CS_PIX0_DARKGREEN:	EQU 4
	;[317] CONST CS_PIX0_GREEN					= 5
	SRCFILE "constants.bas",317
const_CS_PIX0_GREEN:	EQU 5
	;[318] CONST CS_PIX0_YELLOW				= 6
	SRCFILE "constants.bas",318
const_CS_PIX0_YELLOW:	EQU 6
	;[319] CONST CS_PIX0_BACKGROUND			= 7
	SRCFILE "constants.bas",319
const_CS_PIX0_BACKGROUND:	EQU 7
	;[320] CONST CS_PIX1_BLACK					= 0
	SRCFILE "constants.bas",320
const_CS_PIX1_BLACK:	EQU 0
	;[321] CONST CS_PIX1_BLUE					= 1*8
	SRCFILE "constants.bas",321
const_CS_PIX1_BLUE:	EQU 8
	;[322] CONST CS_PIX1_RED					= 2*8
	SRCFILE "constants.bas",322
const_CS_PIX1_RED:	EQU 16
	;[323] CONST CS_PIX1_TAN					= 3*8
	SRCFILE "constants.bas",323
const_CS_PIX1_TAN:	EQU 24
	;[324] CONST CS_PIX1_DARKGREEN				= 4*8
	SRCFILE "constants.bas",324
const_CS_PIX1_DARKGREEN:	EQU 32
	;[325] CONST CS_PIX1_GREEN					= 5*8
	SRCFILE "constants.bas",325
const_CS_PIX1_GREEN:	EQU 40
	;[326] CONST CS_PIX1_YELLOW				= 6*8
	SRCFILE "constants.bas",326
const_CS_PIX1_YELLOW:	EQU 48
	;[327] CONST CS_PIX1_BACKGROUND			= 7*8
	SRCFILE "constants.bas",327
const_CS_PIX1_BACKGROUND:	EQU 56
	;[328] CONST CS_PIX2_BLACK					= 0
	SRCFILE "constants.bas",328
const_CS_PIX2_BLACK:	EQU 0
	;[329] CONST CS_PIX2_BLUE					= 1*64
	SRCFILE "constants.bas",329
const_CS_PIX2_BLUE:	EQU 64
	;[330] CONST CS_PIX2_RED					= 2*64
	SRCFILE "constants.bas",330
const_CS_PIX2_RED:	EQU 128
	;[331] CONST CS_PIX2_TAN					= 3*64
	SRCFILE "constants.bas",331
const_CS_PIX2_TAN:	EQU 192
	;[332] CONST CS_PIX2_DARKGREEN				= 4*64
	SRCFILE "constants.bas",332
const_CS_PIX2_DARKGREEN:	EQU 256
	;[333] CONST CS_PIX2_GREEN					= 5*64
	SRCFILE "constants.bas",333
const_CS_PIX2_GREEN:	EQU 320
	;[334] CONST CS_PIX2_YELLOW				= 6*64
	SRCFILE "constants.bas",334
const_CS_PIX2_YELLOW:	EQU 384
	;[335] CONST CS_PIX2_BACKGROUND			= 7*64
	SRCFILE "constants.bas",335
const_CS_PIX2_BACKGROUND:	EQU 448
	;[336] CONST CS_PIX3_BLACK					= 0
	SRCFILE "constants.bas",336
const_CS_PIX3_BLACK:	EQU 0
	;[337] CONST CS_PIX3_BLUE					= $0200
	SRCFILE "constants.bas",337
const_CS_PIX3_BLUE:	EQU 512
	;[338] CONST CS_PIX3_RED					= $0400
	SRCFILE "constants.bas",338
const_CS_PIX3_RED:	EQU 1024
	;[339] CONST CS_PIX3_TAN					= $0600
	SRCFILE "constants.bas",339
const_CS_PIX3_TAN:	EQU 1536
	;[340] CONST CS_PIX3_DARKGREEN				= $2000
	SRCFILE "constants.bas",340
const_CS_PIX3_DARKGREEN:	EQU 8192
	;[341] CONST CS_PIX3_GREEN					= $2200
	SRCFILE "constants.bas",341
const_CS_PIX3_GREEN:	EQU 8704
	;[342] CONST CS_PIX3_YELLOW				= $2400
	SRCFILE "constants.bas",342
const_CS_PIX3_YELLOW:	EQU 9216
	;[343] CONST CS_PIX3_BACKGROUND			= $2600
	SRCFILE "constants.bas",343
const_CS_PIX3_BACKGROUND:	EQU 9728
	;[344] CONST CS_PIX_MASK					= CS_COLOUR_SQUARES_ENABLE+CS_PIX0_BACKGROUND+CS_PIX1_BACKGROUND+CS_PIX2_BACKGROUND+CS_PIX3_BACKGROUND
	SRCFILE "constants.bas",344
const_CS_PIX_MASK:	EQU 14335
	;[345] 
	SRCFILE "constants.bas",345
	;[346] CONST CS_PIX_X_MIN					= 0		' Minimum x coordinate.
	SRCFILE "constants.bas",346
const_CS_PIX_X_MIN:	EQU 0
	;[347] CONST CS_PIX_X_MAX					= 39	' Maximum x coordinate.
	SRCFILE "constants.bas",347
const_CS_PIX_X_MAX:	EQU 39
	;[348] CONST CS_PIX_Y_MIN					= 0		' Minimum Y coordinate.
	SRCFILE "constants.bas",348
const_CS_PIX_Y_MIN:	EQU 0
	;[349] CONST CS_PIX_Y_MAX					= 23	' Maximum Y coordinate.
	SRCFILE "constants.bas",349
const_CS_PIX_Y_MAX:	EQU 23
	;[350] 
	SRCFILE "constants.bas",350
	;[351] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",351
	;[352] 
	SRCFILE "constants.bas",352
	;[353] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",353
	;[354] REM COLORS - Mode 1 (Foreground Background)
	SRCFILE "constants.bas",354
	;[355] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",355
	;[356] REM Foreground.
	SRCFILE "constants.bas",356
	;[357] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",357
	;[358] REM Notes:
	SRCFILE "constants.bas",358
	;[359] REM - For use with "peek/poke" commands that access BACKTAB.
	SRCFILE "constants.bas",359
	;[360] REM - Only one foreground colour permitted per background card.
	SRCFILE "constants.bas",360
	;[361] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",361
	;[362] CONST FG_BLACK						= $0000
	SRCFILE "constants.bas",362
const_FG_BLACK:	EQU 0
	;[363] CONST FG_BLUE						= $0001
	SRCFILE "constants.bas",363
const_FG_BLUE:	EQU 1
	;[364] CONST FG_RED						= $0002
	SRCFILE "constants.bas",364
const_FG_RED:	EQU 2
	;[365] CONST FG_TAN						= $0003
	SRCFILE "constants.bas",365
const_FG_TAN:	EQU 3
	;[366] CONST FG_DARKGREEN					= $0004
	SRCFILE "constants.bas",366
const_FG_DARKGREEN:	EQU 4
	;[367] CONST FG_GREEN						= $0005
	SRCFILE "constants.bas",367
const_FG_GREEN:	EQU 5
	;[368] CONST FG_YELLOW						= $0006
	SRCFILE "constants.bas",368
const_FG_YELLOW:	EQU 6
	;[369] CONST FG_WHITE						= $0007
	SRCFILE "constants.bas",369
const_FG_WHITE:	EQU 7
	;[370] 
	SRCFILE "constants.bas",370
	;[371] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",371
	;[372] REM Background.
	SRCFILE "constants.bas",372
	;[373] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",373
	;[374] REM Notes:
	SRCFILE "constants.bas",374
	;[375] REM - For use with "peek/poke" commands that access BACKTAB.
	SRCFILE "constants.bas",375
	;[376] REM - Only one background colour permitted per background card.
	SRCFILE "constants.bas",376
	;[377] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",377
	;[378] CONST BG_BLACK						= $0000
	SRCFILE "constants.bas",378
const_BG_BLACK:	EQU 0
	;[379] CONST BG_BLUE						= $0200
	SRCFILE "constants.bas",379
const_BG_BLUE:	EQU 512
	;[380] CONST BG_RED						= $0400
	SRCFILE "constants.bas",380
const_BG_RED:	EQU 1024
	;[381] CONST BG_TAN						= $0600
	SRCFILE "constants.bas",381
const_BG_TAN:	EQU 1536
	;[382] CONST BG_DARKGREEN					= $2000
	SRCFILE "constants.bas",382
const_BG_DARKGREEN:	EQU 8192
	;[383] CONST BG_GREEN						= $2200
	SRCFILE "constants.bas",383
const_BG_GREEN:	EQU 8704
	;[384] CONST BG_YELLOW						= $2400
	SRCFILE "constants.bas",384
const_BG_YELLOW:	EQU 9216
	;[385] CONST BG_WHITE						= $2600
	SRCFILE "constants.bas",385
const_BG_WHITE:	EQU 9728
	;[386] CONST BG_GREY						= $1000
	SRCFILE "constants.bas",386
const_BG_GREY:	EQU 4096
	;[387] CONST BG_CYAN						= $1200
	SRCFILE "constants.bas",387
const_BG_CYAN:	EQU 4608
	;[388] CONST BG_ORANGE						= $1400
	SRCFILE "constants.bas",388
const_BG_ORANGE:	EQU 5120
	;[389] CONST BG_BROWN						= $1600
	SRCFILE "constants.bas",389
const_BG_BROWN:	EQU 5632
	;[390] CONST BG_PINK						= $3000
	SRCFILE "constants.bas",390
const_BG_PINK:	EQU 12288
	;[391] CONST BG_LIGHTBLUE					= $3200
	SRCFILE "constants.bas",391
const_BG_LIGHTBLUE:	EQU 12800
	;[392] CONST BG_YELLOWGREEN				= $3400
	SRCFILE "constants.bas",392
const_BG_YELLOWGREEN:	EQU 13312
	;[393] CONST BG_PURPLE						= $3600
	SRCFILE "constants.bas",393
const_BG_PURPLE:	EQU 13824
	;[394] 
	SRCFILE "constants.bas",394
	;[395] CONST FGBG_CARD_DATA_MASK			= $01F8		' Mask to get the background card's data.
	SRCFILE "constants.bas",395
const_FGBG_CARD_DATA_MASK:	EQU 504
	;[396] 
	SRCFILE "constants.bas",396
	;[397] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",397
	;[398] 
	SRCFILE "constants.bas",398
	;[399] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",399
	;[400] REM Sprites.
	SRCFILE "constants.bas",400
	;[401] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",401
	;[402] REM Note: For use with "sprite" command.
	SRCFILE "constants.bas",402
	;[403] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",403
	;[404] REM X
	SRCFILE "constants.bas",404
	;[405] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",405
	;[406] REM Note: Add these constants to the sprite command's X parameter.
	SRCFILE "constants.bas",406
	;[407] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",407
	;[408] CONST HIT							= $0100		' Enable the sprite's collision detection.
	SRCFILE "constants.bas",408
const_HIT:	EQU 256
	;[409] CONST VISIBLE						= $0200		' Make the sprite visible.
	SRCFILE "constants.bas",409
const_VISIBLE:	EQU 512
	;[410] CONST ZOOMX2						= $0400		' Make the sprite twice the width.
	SRCFILE "constants.bas",410
const_ZOOMX2:	EQU 1024
	;[411] 
	SRCFILE "constants.bas",411
	;[412] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",412
	;[413] REM Y
	SRCFILE "constants.bas",413
	;[414] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",414
	;[415] REM Note: Add these constants to the sprite command's Y parameter.
	SRCFILE "constants.bas",415
	;[416] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",416
	;[417] CONST DOUBLEY						= $0080		' Make a double height sprite (with 2 GRAM cards).
	SRCFILE "constants.bas",417
const_DOUBLEY:	EQU 128
	;[418] CONST ZOOMY2						= $0100		' Make the sprite twice (x2) the normal height.
	SRCFILE "constants.bas",418
const_ZOOMY2:	EQU 256
	;[419] CONST ZOOMY4						= $0200		' Make the sprite quadruple (x4) the normal height.
	SRCFILE "constants.bas",419
const_ZOOMY4:	EQU 512
	;[420] CONST ZOOMY8						= $0300		' Make the sprite octuple (x8) the normal height.
	SRCFILE "constants.bas",420
const_ZOOMY8:	EQU 768
	;[421] CONST FLIPX							= $0400		' Flip/mirror the sprite in X.
	SRCFILE "constants.bas",421
const_FLIPX:	EQU 1024
	;[422] CONST FLIPY							= $0800		' Flip/mirror the sprite in Y.
	SRCFILE "constants.bas",422
const_FLIPY:	EQU 2048
	;[423] CONST MIRROR						= $0C00		' Flip/mirror the sprite in both X and Y.
	SRCFILE "constants.bas",423
const_MIRROR:	EQU 3072
	;[424] 
	SRCFILE "constants.bas",424
	;[425] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",425
	;[426] REM A
	SRCFILE "constants.bas",426
	;[427] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",427
	;[428] REM Notes:
	SRCFILE "constants.bas",428
	;[429] REM - Combine to create the sprite command's A parameter.
	SRCFILE "constants.bas",429
	;[430] REM - Only one colour per sprite.
	SRCFILE "constants.bas",430
	;[431] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",431
	;[432] CONST GRAM							= $0800		' Sprite's data is located in GRAM.
	SRCFILE "constants.bas",432
const_GRAM:	EQU 2048
	;[433] CONST BEHIND						= $2000		' Sprite is behind the background.
	SRCFILE "constants.bas",433
const_BEHIND:	EQU 8192
	;[434] CONST SPR_BLACK						= $0000
	SRCFILE "constants.bas",434
const_SPR_BLACK:	EQU 0
	;[435] CONST SPR_BLUE						= $0001
	SRCFILE "constants.bas",435
const_SPR_BLUE:	EQU 1
	;[436] CONST SPR_RED						= $0002
	SRCFILE "constants.bas",436
const_SPR_RED:	EQU 2
	;[437] CONST SPR_TAN						= $0003
	SRCFILE "constants.bas",437
const_SPR_TAN:	EQU 3
	;[438] CONST SPR_DARKGREEN					= $0004
	SRCFILE "constants.bas",438
const_SPR_DARKGREEN:	EQU 4
	;[439] CONST SPR_GREEN						= $0005
	SRCFILE "constants.bas",439
const_SPR_GREEN:	EQU 5
	;[440] CONST SPR_YELLOW					= $0006
	SRCFILE "constants.bas",440
const_SPR_YELLOW:	EQU 6
	;[441] CONST SPR_WHITE						= $0007
	SRCFILE "constants.bas",441
const_SPR_WHITE:	EQU 7
	;[442] CONST SPR_GREY						= $1000
	SRCFILE "constants.bas",442
const_SPR_GREY:	EQU 4096
	;[443] CONST SPR_CYAN						= $1001
	SRCFILE "constants.bas",443
const_SPR_CYAN:	EQU 4097
	;[444] CONST SPR_ORANGE					= $1002
	SRCFILE "constants.bas",444
const_SPR_ORANGE:	EQU 4098
	;[445] CONST SPR_BROWN						= $1003
	SRCFILE "constants.bas",445
const_SPR_BROWN:	EQU 4099
	;[446] CONST SPR_PINK						= $1004
	SRCFILE "constants.bas",446
const_SPR_PINK:	EQU 4100
	;[447] CONST SPR_LIGHTBLUE					= $1005
	SRCFILE "constants.bas",447
const_SPR_LIGHTBLUE:	EQU 4101
	;[448] CONST SPR_YELLOWGREEN				= $1006
	SRCFILE "constants.bas",448
const_SPR_YELLOWGREEN:	EQU 4102
	;[449] CONST SPR_PURPLE					= $1007
	SRCFILE "constants.bas",449
const_SPR_PURPLE:	EQU 4103
	;[450] 
	SRCFILE "constants.bas",450
	;[451] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",451
	;[452] REM GRAM numbers.
	SRCFILE "constants.bas",452
	;[453] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",453
	;[454] REM Note: For use in the sprite command's parameter A.
	SRCFILE "constants.bas",454
	;[455] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",455
	;[456] CONST SPR00							= $0800
	SRCFILE "constants.bas",456
const_SPR00:	EQU 2048
	;[457] CONST SPR01							= $0808
	SRCFILE "constants.bas",457
const_SPR01:	EQU 2056
	;[458] CONST SPR02							= $0810
	SRCFILE "constants.bas",458
const_SPR02:	EQU 2064
	;[459] CONST SPR03							= $0818
	SRCFILE "constants.bas",459
const_SPR03:	EQU 2072
	;[460] CONST SPR04							= $0820
	SRCFILE "constants.bas",460
const_SPR04:	EQU 2080
	;[461] CONST SPR05							= $0828
	SRCFILE "constants.bas",461
const_SPR05:	EQU 2088
	;[462] CONST SPR06							= $0830
	SRCFILE "constants.bas",462
const_SPR06:	EQU 2096
	;[463] CONST SPR07							= $0838
	SRCFILE "constants.bas",463
const_SPR07:	EQU 2104
	;[464] CONST SPR08							= $0840
	SRCFILE "constants.bas",464
const_SPR08:	EQU 2112
	;[465] CONST SPR09							= $0848
	SRCFILE "constants.bas",465
const_SPR09:	EQU 2120
	;[466] CONST SPR10							= $0850
	SRCFILE "constants.bas",466
const_SPR10:	EQU 2128
	;[467] CONST SPR11							= $0858
	SRCFILE "constants.bas",467
const_SPR11:	EQU 2136
	;[468] CONST SPR12							= $0860
	SRCFILE "constants.bas",468
const_SPR12:	EQU 2144
	;[469] CONST SPR13							= $0868
	SRCFILE "constants.bas",469
const_SPR13:	EQU 2152
	;[470] CONST SPR14							= $0870
	SRCFILE "constants.bas",470
const_SPR14:	EQU 2160
	;[471] CONST SPR15							= $0878
	SRCFILE "constants.bas",471
const_SPR15:	EQU 2168
	;[472] CONST SPR16							= $0880
	SRCFILE "constants.bas",472
const_SPR16:	EQU 2176
	;[473] CONST SPR17							= $0888
	SRCFILE "constants.bas",473
const_SPR17:	EQU 2184
	;[474] CONST SPR18							= $0890
	SRCFILE "constants.bas",474
const_SPR18:	EQU 2192
	;[475] CONST SPR19							= $0898
	SRCFILE "constants.bas",475
const_SPR19:	EQU 2200
	;[476] CONST SPR20							= $08A0
	SRCFILE "constants.bas",476
const_SPR20:	EQU 2208
	;[477] CONST SPR21							= $08A8
	SRCFILE "constants.bas",477
const_SPR21:	EQU 2216
	;[478] CONST SPR22							= $08B0
	SRCFILE "constants.bas",478
const_SPR22:	EQU 2224
	;[479] CONST SPR23							= $08B8
	SRCFILE "constants.bas",479
const_SPR23:	EQU 2232
	;[480] CONST SPR24							= $08C0
	SRCFILE "constants.bas",480
const_SPR24:	EQU 2240
	;[481] CONST SPR25							= $08C8
	SRCFILE "constants.bas",481
const_SPR25:	EQU 2248
	;[482] CONST SPR26							= $08D0
	SRCFILE "constants.bas",482
const_SPR26:	EQU 2256
	;[483] CONST SPR27							= $08D8
	SRCFILE "constants.bas",483
const_SPR27:	EQU 2264
	;[484] CONST SPR28							= $08E0
	SRCFILE "constants.bas",484
const_SPR28:	EQU 2272
	;[485] CONST SPR29							= $08E8
	SRCFILE "constants.bas",485
const_SPR29:	EQU 2280
	;[486] CONST SPR30							= $08F0
	SRCFILE "constants.bas",486
const_SPR30:	EQU 2288
	;[487] CONST SPR31							= $08F8
	SRCFILE "constants.bas",487
const_SPR31:	EQU 2296
	;[488] CONST SPR32							= $0900
	SRCFILE "constants.bas",488
const_SPR32:	EQU 2304
	;[489] CONST SPR33							= $0908
	SRCFILE "constants.bas",489
const_SPR33:	EQU 2312
	;[490] CONST SPR34							= $0910
	SRCFILE "constants.bas",490
const_SPR34:	EQU 2320
	;[491] CONST SPR35							= $0918
	SRCFILE "constants.bas",491
const_SPR35:	EQU 2328
	;[492] CONST SPR36							= $0920
	SRCFILE "constants.bas",492
const_SPR36:	EQU 2336
	;[493] CONST SPR37							= $0928
	SRCFILE "constants.bas",493
const_SPR37:	EQU 2344
	;[494] CONST SPR38							= $0930
	SRCFILE "constants.bas",494
const_SPR38:	EQU 2352
	;[495] CONST SPR39							= $0938
	SRCFILE "constants.bas",495
const_SPR39:	EQU 2360
	;[496] CONST SPR40							= $0940
	SRCFILE "constants.bas",496
const_SPR40:	EQU 2368
	;[497] CONST SPR41							= $0948
	SRCFILE "constants.bas",497
const_SPR41:	EQU 2376
	;[498] CONST SPR42							= $0950
	SRCFILE "constants.bas",498
const_SPR42:	EQU 2384
	;[499] CONST SPR43							= $0958
	SRCFILE "constants.bas",499
const_SPR43:	EQU 2392
	;[500] CONST SPR44							= $0960
	SRCFILE "constants.bas",500
const_SPR44:	EQU 2400
	;[501] CONST SPR45							= $0968
	SRCFILE "constants.bas",501
const_SPR45:	EQU 2408
	;[502] CONST SPR46							= $0970
	SRCFILE "constants.bas",502
const_SPR46:	EQU 2416
	;[503] CONST SPR47							= $0978
	SRCFILE "constants.bas",503
const_SPR47:	EQU 2424
	;[504] CONST SPR48							= $0980
	SRCFILE "constants.bas",504
const_SPR48:	EQU 2432
	;[505] CONST SPR49							= $0988
	SRCFILE "constants.bas",505
const_SPR49:	EQU 2440
	;[506] CONST SPR50							= $0990
	SRCFILE "constants.bas",506
const_SPR50:	EQU 2448
	;[507] CONST SPR51							= $0998
	SRCFILE "constants.bas",507
const_SPR51:	EQU 2456
	;[508] CONST SPR52							= $09A0
	SRCFILE "constants.bas",508
const_SPR52:	EQU 2464
	;[509] CONST SPR53							= $09A8
	SRCFILE "constants.bas",509
const_SPR53:	EQU 2472
	;[510] CONST SPR54							= $09B0
	SRCFILE "constants.bas",510
const_SPR54:	EQU 2480
	;[511] CONST SPR55							= $09B8
	SRCFILE "constants.bas",511
const_SPR55:	EQU 2488
	;[512] CONST SPR56							= $09C0
	SRCFILE "constants.bas",512
const_SPR56:	EQU 2496
	;[513] CONST SPR57							= $09C8
	SRCFILE "constants.bas",513
const_SPR57:	EQU 2504
	;[514] CONST SPR58							= $09D0
	SRCFILE "constants.bas",514
const_SPR58:	EQU 2512
	;[515] CONST SPR59							= $09D8
	SRCFILE "constants.bas",515
const_SPR59:	EQU 2520
	;[516] CONST SPR60							= $09E0
	SRCFILE "constants.bas",516
const_SPR60:	EQU 2528
	;[517] CONST SPR61							= $09E8
	SRCFILE "constants.bas",517
const_SPR61:	EQU 2536
	;[518] CONST SPR62							= $09F0
	SRCFILE "constants.bas",518
const_SPR62:	EQU 2544
	;[519] CONST SPR63							= $09F8
	SRCFILE "constants.bas",519
const_SPR63:	EQU 2552
	;[520] 
	SRCFILE "constants.bas",520
	;[521] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",521
	;[522] REM Sprite collision.
	SRCFILE "constants.bas",522
	;[523] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",523
	;[524] REM Notes:
	SRCFILE "constants.bas",524
	;[525] REM - For use with variables COL0, COL1, COL2, COL3, COL4, COL5, COL6 and COL7.
	SRCFILE "constants.bas",525
	;[526] REM - More than one collision can occur simultaneously.
	SRCFILE "constants.bas",526
	;[527] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",527
	;[528] CONST HIT_SPRITE0					= $0001		' Sprite collided with sprite 0.
	SRCFILE "constants.bas",528
const_HIT_SPRITE0:	EQU 1
	;[529] CONST HIT_SPRITE1					= $0002		' Sprite collided with sprite 1.
	SRCFILE "constants.bas",529
const_HIT_SPRITE1:	EQU 2
	;[530] CONST HIT_SPRITE2					= $0004		' Sprite collided with sprite 2.
	SRCFILE "constants.bas",530
const_HIT_SPRITE2:	EQU 4
	;[531] CONST HIT_SPRITE3					= $0008		' Sprite collided with sprite 3.
	SRCFILE "constants.bas",531
const_HIT_SPRITE3:	EQU 8
	;[532] CONST HIT_SPRITE4					= $0010		' Sprite collided with sprite 4.
	SRCFILE "constants.bas",532
const_HIT_SPRITE4:	EQU 16
	;[533] CONST HIT_SPRITE5					= $0020		' Sprite collided with sprite 5.
	SRCFILE "constants.bas",533
const_HIT_SPRITE5:	EQU 32
	;[534] CONST HIT_SPRITE6					= $0040		' Sprite collided with sprite 6.
	SRCFILE "constants.bas",534
const_HIT_SPRITE6:	EQU 64
	;[535] CONST HIT_SPRITE7					= $0080		' Sprite collided with sprite 7.
	SRCFILE "constants.bas",535
const_HIT_SPRITE7:	EQU 128
	;[536] CONST HIT_BACKGROUND				= $0100		' Sprite collided with a background pixel.
	SRCFILE "constants.bas",536
const_HIT_BACKGROUND:	EQU 256
	;[537] CONST HIT_BORDER					= $0200		' Sprite collided with the top/bottom/left/right border.
	SRCFILE "constants.bas",537
const_HIT_BORDER:	EQU 512
	;[538] 
	SRCFILE "constants.bas",538
	;[539] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",539
	;[540] 
	SRCFILE "constants.bas",540
	;[541] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",541
	;[542] REM DISC - Compass.
	SRCFILE "constants.bas",542
	;[543] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",543
	;[544] REM   NW         N         NE
	SRCFILE "constants.bas",544
	;[545] REM     \   NNW  |  NNE   /
	SRCFILE "constants.bas",545
	;[546] REM       \      |      /
	SRCFILE "constants.bas",546
	;[547] REM         \    |    /
	SRCFILE "constants.bas",547
	;[548] REM    WNW    \  |  /    ENE
	SRCFILE "constants.bas",548
	;[549] REM             \|/
	SRCFILE "constants.bas",549
	;[550] REM  W ----------+---------- E
	SRCFILE "constants.bas",550
	;[552] REM             /|REM    WSW    /  |  \    ESE
	SRCFILE "constants.bas",552
	;[556] REM         /    |    REM       /      |      REM     /   SSW  |  SSE   REM   SW         S         SE
	SRCFILE "constants.bas",556
	;[557] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",557
	;[558] REM Notes:
	SRCFILE "constants.bas",558
	;[559] REM - North points upwards on the hand controller.
	SRCFILE "constants.bas",559
	;[560] REM - Directions are listed in a clockwise manner.
	SRCFILE "constants.bas",560
	;[561] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",561
	;[562] CONST DISC_NORTH					= $0004
	SRCFILE "constants.bas",562
const_DISC_NORTH:	EQU 4
	;[563] CONST DISC_NORTH_NORTH_EAST 		= $0014
	SRCFILE "constants.bas",563
const_DISC_NORTH_NORTH_EAST:	EQU 20
	;[564] CONST DISC_NORTH_EAST				= $0016
	SRCFILE "constants.bas",564
const_DISC_NORTH_EAST:	EQU 22
	;[565] CONST DISC_EAST_NORTH_EAST			= $0006
	SRCFILE "constants.bas",565
const_DISC_EAST_NORTH_EAST:	EQU 6
	;[566] CONST DISC_EAST						= $0002
	SRCFILE "constants.bas",566
const_DISC_EAST:	EQU 2
	;[567] CONST DISC_EAST_SOUTH_EAST			= $0012
	SRCFILE "constants.bas",567
const_DISC_EAST_SOUTH_EAST:	EQU 18
	;[568] CONST DISC_SOUTH_EAST				= $0013
	SRCFILE "constants.bas",568
const_DISC_SOUTH_EAST:	EQU 19
	;[569] CONST DISC_SOUTH_SOUTH_EAST			= $0003
	SRCFILE "constants.bas",569
const_DISC_SOUTH_SOUTH_EAST:	EQU 3
	;[570] CONST DISC_SOUTH					= $0001
	SRCFILE "constants.bas",570
const_DISC_SOUTH:	EQU 1
	;[571] CONST DISC_SOUTH_SOUTH_WEST			= $0011
	SRCFILE "constants.bas",571
const_DISC_SOUTH_SOUTH_WEST:	EQU 17
	;[572] CONST DISC_SOUTH_WEST				= $0019
	SRCFILE "constants.bas",572
const_DISC_SOUTH_WEST:	EQU 25
	;[573] CONST DISC_WEST_SOUTH_WEST			= $0009
	SRCFILE "constants.bas",573
const_DISC_WEST_SOUTH_WEST:	EQU 9
	;[574] CONST DISC_WEST						= $0008
	SRCFILE "constants.bas",574
const_DISC_WEST:	EQU 8
	;[575] CONST DISC_WEST_NORTH_WEST			= $0018
	SRCFILE "constants.bas",575
const_DISC_WEST_NORTH_WEST:	EQU 24
	;[576] CONST DISC_NORTH_WEST				= $001C
	SRCFILE "constants.bas",576
const_DISC_NORTH_WEST:	EQU 28
	;[577] CONST DISC_NORTH_NORTH_WEST			= $000C
	SRCFILE "constants.bas",577
const_DISC_NORTH_NORTH_WEST:	EQU 12
	;[578] 
	SRCFILE "constants.bas",578
	;[579] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",579
	;[580] REM DISC - Compass abbreviated versions.
	SRCFILE "constants.bas",580
	;[581] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",581
	;[582] CONST DISC_N						= $0004
	SRCFILE "constants.bas",582
const_DISC_N:	EQU 4
	;[583] CONST DISC_NNE						= $0014
	SRCFILE "constants.bas",583
const_DISC_NNE:	EQU 20
	;[584] CONST DISC_NE						= $0016
	SRCFILE "constants.bas",584
const_DISC_NE:	EQU 22
	;[585] CONST DISC_ENE						= $0006
	SRCFILE "constants.bas",585
const_DISC_ENE:	EQU 6
	;[586] CONST DISC_E						= $0002
	SRCFILE "constants.bas",586
const_DISC_E:	EQU 2
	;[587] CONST DISC_ESE						= $0012
	SRCFILE "constants.bas",587
const_DISC_ESE:	EQU 18
	;[588] CONST DISC_SE						= $0013
	SRCFILE "constants.bas",588
const_DISC_SE:	EQU 19
	;[589] CONST DISC_SSE						= $0003
	SRCFILE "constants.bas",589
const_DISC_SSE:	EQU 3
	;[590] CONST DISC_S						= $0001
	SRCFILE "constants.bas",590
const_DISC_S:	EQU 1
	;[591] CONST DISC_SSW						= $0011
	SRCFILE "constants.bas",591
const_DISC_SSW:	EQU 17
	;[592] CONST DISC_SW						= $0019
	SRCFILE "constants.bas",592
const_DISC_SW:	EQU 25
	;[593] CONST DISC_WSW						= $0009
	SRCFILE "constants.bas",593
const_DISC_WSW:	EQU 9
	;[594] CONST DISC_W						= $0008
	SRCFILE "constants.bas",594
const_DISC_W:	EQU 8
	;[595] CONST DISC_WNW						= $0018
	SRCFILE "constants.bas",595
const_DISC_WNW:	EQU 24
	;[596] CONST DISC_NW						= $001C
	SRCFILE "constants.bas",596
const_DISC_NW:	EQU 28
	;[597] CONST DISC_NNW						= $000C
	SRCFILE "constants.bas",597
const_DISC_NNW:	EQU 12
	;[598] 
	SRCFILE "constants.bas",598
	;[599] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",599
	;[600] REM DISC - Directions.
	SRCFILE "constants.bas",600
	;[601] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",601
	;[602] CONST DISC_UP						= $0004
	SRCFILE "constants.bas",602
const_DISC_UP:	EQU 4
	;[603] CONST DISC_UP_RIGHT					= $0016		' Up and right diagonal.
	SRCFILE "constants.bas",603
const_DISC_UP_RIGHT:	EQU 22
	;[604] CONST DISC_RIGHT					= $0002
	SRCFILE "constants.bas",604
const_DISC_RIGHT:	EQU 2
	;[605] CONST DISC_DOWN_RIGHT				= $0013		' Down  and right diagonal.
	SRCFILE "constants.bas",605
const_DISC_DOWN_RIGHT:	EQU 19
	;[606] CONST DISC_DOWN						= $0001
	SRCFILE "constants.bas",606
const_DISC_DOWN:	EQU 1
	;[607] CONST DISC_DOWN_LEFT				= $0019		' Down and left diagonal.
	SRCFILE "constants.bas",607
const_DISC_DOWN_LEFT:	EQU 25
	;[608] CONST DISC_LEFT						= $0008
	SRCFILE "constants.bas",608
const_DISC_LEFT:	EQU 8
	;[609] CONST DISC_UP_LEFT					= $001C		' Up and left diagonal.
	SRCFILE "constants.bas",609
const_DISC_UP_LEFT:	EQU 28
	;[610] 
	SRCFILE "constants.bas",610
	;[611] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",611
	;[612] REM DISK - Mask.
	SRCFILE "constants.bas",612
	;[613] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",613
	;[614] CONST DISK_MASK						= $001F
	SRCFILE "constants.bas",614
const_DISK_MASK:	EQU 31
	;[615] 
	SRCFILE "constants.bas",615
	;[616] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",616
	;[617] REM Controller - Keypad.
	SRCFILE "constants.bas",617
	;[618] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",618
	;[619] CONST KEYPAD_0						= 72
	SRCFILE "constants.bas",619
const_KEYPAD_0:	EQU 72
	;[620] CONST KEYPAD_1						= 129
	SRCFILE "constants.bas",620
const_KEYPAD_1:	EQU 129
	;[621] CONST KEYPAD_2						= 65
	SRCFILE "constants.bas",621
const_KEYPAD_2:	EQU 65
	;[622] CONST KEYPAD_3						= 33
	SRCFILE "constants.bas",622
const_KEYPAD_3:	EQU 33
	;[623] CONST KEYPAD_4						= 130
	SRCFILE "constants.bas",623
const_KEYPAD_4:	EQU 130
	;[624] CONST KEYPAD_5						= 66
	SRCFILE "constants.bas",624
const_KEYPAD_5:	EQU 66
	;[625] CONST KEYPAD_6						= 34
	SRCFILE "constants.bas",625
const_KEYPAD_6:	EQU 34
	;[626] CONST KEYPAD_7						= 132
	SRCFILE "constants.bas",626
const_KEYPAD_7:	EQU 132
	;[627] CONST KEYPAD_8						= 68
	SRCFILE "constants.bas",627
const_KEYPAD_8:	EQU 68
	;[628] CONST KEYPAD_9						= 36
	SRCFILE "constants.bas",628
const_KEYPAD_9:	EQU 36
	;[629] CONST KEYPAD_CLEAR					= 136
	SRCFILE "constants.bas",629
const_KEYPAD_CLEAR:	EQU 136
	;[630] CONST KEYPAD_ENTER					= 40
	SRCFILE "constants.bas",630
const_KEYPAD_ENTER:	EQU 40
	;[631] 
	SRCFILE "constants.bas",631
	;[632] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",632
	;[633] REM Controller - Pause buttons (1+9 or 3+7 held down simultaneously).
	SRCFILE "constants.bas",633
	;[634] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",634
	;[635] REM Notes:
	SRCFILE "constants.bas",635
	;[636] REM - Key codes for 3+7 and 1+9 are the same (165).
	SRCFILE "constants.bas",636
	;[637] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",637
	;[638] CONST KEYPAD_PAUSE					= (KEYPAD_1 XOR KEYPAD_9)
	SRCFILE "constants.bas",638
const_KEYPAD_PAUSE:	EQU 165
	;[639] 
	SRCFILE "constants.bas",639
	;[640] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",640
	;[641] REM Controller - Side buttons.
	SRCFILE "constants.bas",641
	;[642] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",642
	;[643] CONST BUTTON_TOP_LEFT				= $A0		' Top left and top right are the same button.
	SRCFILE "constants.bas",643
const_BUTTON_TOP_LEFT:	EQU 160
	;[644] CONST BUTTON_TOP_RIGHT				= $A0		' Note: Bit 6 is low.
	SRCFILE "constants.bas",644
const_BUTTON_TOP_RIGHT:	EQU 160
	;[645] CONST BUTTON_BOTTOM_LEFT			= $60		' Note: Bit 7 is low.
	SRCFILE "constants.bas",645
const_BUTTON_BOTTOM_LEFT:	EQU 96
	;[646] CONST BUTTON_BOTTOM_RIGHT			= $C0		' Note: Bit 5 is low
	SRCFILE "constants.bas",646
const_BUTTON_BOTTOM_RIGHT:	EQU 192
	;[647] 
	SRCFILE "constants.bas",647
	;[648] REM Abbreviated versions.
	SRCFILE "constants.bas",648
	;[649] CONST BUTTON_1						= $A0		' Top left or top right.
	SRCFILE "constants.bas",649
const_BUTTON_1:	EQU 160
	;[650] CONST BUTTON_2						= $60		' Bottom left.
	SRCFILE "constants.bas",650
const_BUTTON_2:	EQU 96
	;[651] CONST BUTTON_3						= $C0		' Bottom right.
	SRCFILE "constants.bas",651
const_BUTTON_3:	EQU 192
	;[652] 
	SRCFILE "constants.bas",652
	;[653] REM Mask.
	SRCFILE "constants.bas",653
	;[654] CONST BUTTON_MASK					= $E0
	SRCFILE "constants.bas",654
const_BUTTON_MASK:	EQU 224
	;[655] 
	SRCFILE "constants.bas",655
	;[656] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",656
	;[657] 
	SRCFILE "constants.bas",657
	;[658] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",658
	;[659] REM Programmable Sound Generator (PSG)
	SRCFILE "constants.bas",659
	;[660] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",660
	;[661] REM Notes:
	SRCFILE "constants.bas",661
	;[662] REM - For use with the SOUND command
	SRCFILE "constants.bas",662
	;[663] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",663
	;[664] 
	SRCFILE "constants.bas",664
	;[665] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",665
	;[666] REM Internal sound hardware.
	SRCFILE "constants.bas",666
	;[667] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",667
	;[668] CONST PSG_CHANNELA					= 0
	SRCFILE "constants.bas",668
const_PSG_CHANNELA:	EQU 0
	;[669] CONST PSG_CHANNELB					= 1
	SRCFILE "constants.bas",669
const_PSG_CHANNELB:	EQU 1
	;[670] CONST PSG_CHANNELC					= 2
	SRCFILE "constants.bas",670
const_PSG_CHANNELC:	EQU 2
	;[671] CONST PSG_ENVELOPE					= 3
	SRCFILE "constants.bas",671
const_PSG_ENVELOPE:	EQU 3
	;[672] CONST PSG_MIXER						= 4
	SRCFILE "constants.bas",672
const_PSG_MIXER:	EQU 4
	;[673] 
	SRCFILE "constants.bas",673
	;[674] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",674
	;[675] REM ECS sound hardware.
	SRCFILE "constants.bas",675
	;[676] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",676
	;[677] CONST PSG_ECS_CHANNELA				= 5
	SRCFILE "constants.bas",677
const_PSG_ECS_CHANNELA:	EQU 5
	;[678] CONST PSG_ECS_CHANNELB				= 6
	SRCFILE "constants.bas",678
const_PSG_ECS_CHANNELB:	EQU 6
	;[679] CONST PSG_ECS_CHANNELC				= 7
	SRCFILE "constants.bas",679
const_PSG_ECS_CHANNELC:	EQU 7
	;[680] CONST PSG_ECS_ENVELOPE				= 8
	SRCFILE "constants.bas",680
const_PSG_ECS_ENVELOPE:	EQU 8
	;[681] CONST PSG_ECS_MIXER					= 9
	SRCFILE "constants.bas",681
const_PSG_ECS_MIXER:	EQU 9
	;[682] 
	SRCFILE "constants.bas",682
	;[683] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",683
	;[684] REM PSG - Volume control.
	SRCFILE "constants.bas",684
	;[685] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",685
	;[686] REM Notes:
	SRCFILE "constants.bas",686
	;[687] REM - For use in the volume field of the SOUND command.
	SRCFILE "constants.bas",687
	;[688] REM - Internal channels: PSG_CHANNELA, PSG_CHANNELB, PSG_CHANNELC
	SRCFILE "constants.bas",688
	;[689] REM - ECS channels: PSG_ECS_CHANNELA, PSG_ECS_CHANNELB, PSG_ECS_CHANNELC
	SRCFILE "constants.bas",689
	;[690] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",690
	;[691] CONST PSG_VOLUME_MAX				= 15	' Maximum channel volume.
	SRCFILE "constants.bas",691
const_PSG_VOLUME_MAX:	EQU 15
	;[692] CONST PSG_ENVELOPE_ENABLE			= 48	' Channel volume is controlled by envelope generator.
	SRCFILE "constants.bas",692
const_PSG_ENVELOPE_ENABLE:	EQU 48
	;[693] 
	SRCFILE "constants.bas",693
	;[694] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",694
	;[695] REM PSG - Mixer control.
	SRCFILE "constants.bas",695
	;[696] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",696
	;[697] REM Notes:
	SRCFILE "constants.bas",697
	;[698] REM - Internal channel: PSG_MIXER
	SRCFILE "constants.bas",698
	;[699] REM - ECS channel: PSG_ECS_MIXER
	SRCFILE "constants.bas",699
	;[700] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",700
	;[701] CONST PSG_TONE_CHANNELA_DISABLE		= $01	' Disable channel A tone.
	SRCFILE "constants.bas",701
const_PSG_TONE_CHANNELA_DISABLE:	EQU 1
	;[702] CONST PSG_TONE_CHANNELB_DISABLE		= $02	' Disable channel B tone.
	SRCFILE "constants.bas",702
const_PSG_TONE_CHANNELB_DISABLE:	EQU 2
	;[703] CONST PSG_TONE_CHANNELC_DISABLE		= $04	' Disable channel C tone.
	SRCFILE "constants.bas",703
const_PSG_TONE_CHANNELC_DISABLE:	EQU 4
	;[704] CONST PSG_NOISE_CHANNELA_DISABLE	= $08	' Disable channel A noise.
	SRCFILE "constants.bas",704
const_PSG_NOISE_CHANNELA_DISABLE:	EQU 8
	;[705] CONST PSG_NOISE_CHANNELB_DISABLE	= $10	' Disable channel B noise.
	SRCFILE "constants.bas",705
const_PSG_NOISE_CHANNELB_DISABLE:	EQU 16
	;[706] CONST PSG_NOISE_CHANNELC_DISABLE	= $20	' Disable channel C noise.
	SRCFILE "constants.bas",706
const_PSG_NOISE_CHANNELC_DISABLE:	EQU 32
	;[707] CONST PSG_MIXER_DEFAULT				= $38 	' All notes enabled. all noise disabled.
	SRCFILE "constants.bas",707
const_PSG_MIXER_DEFAULT:	EQU 56
	;[708] 
	SRCFILE "constants.bas",708
	;[709] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",709
	;[710] REM PSG - Envelope control.
	SRCFILE "constants.bas",710
	;[711] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",711
	;[712] REM Notes:
	SRCFILE "constants.bas",712
	;[713] REM - Internal channel: PSG_ENVELOPE
	SRCFILE "constants.bas",713
	;[714] REM - ECS channel: PSG_ECS_ENVELOPE
	SRCFILE "constants.bas",714
	;[715] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",715
	;[716] CONST PSG_ENVELOPE_HOLD								= $01
	SRCFILE "constants.bas",716
const_PSG_ENVELOPE_HOLD:	EQU 1
	;[717] CONST PSG_ENVELOPE_ALTERNATE						= $02
	SRCFILE "constants.bas",717
const_PSG_ENVELOPE_ALTERNATE:	EQU 2
	;[718] CONST PSG_ENVELOPE_ATTACK							= $04
	SRCFILE "constants.bas",718
const_PSG_ENVELOPE_ATTACK:	EQU 4
	;[719] CONST PSG_ENVELOPE_CONTINUE							= $08
	SRCFILE "constants.bas",719
const_PSG_ENVELOPE_CONTINUE:	EQU 8
	;[720] CONST PSG_ENVELOPE_SINGLE_SHOT_RAMP_DOWN_AND_OFF	= $00 '\______
	SRCFILE "constants.bas",720
const_PSG_ENVELOPE_SINGLE_SHOT_RAMP_DOWN_AND_OFF:	EQU 0
	;[721] CONST PSG_ENVELOPE_SINGLE_SHOT_RAMP_UP_AND_OFF		= $04 '/______
	SRCFILE "constants.bas",721
const_PSG_ENVELOPE_SINGLE_SHOT_RAMP_UP_AND_OFF:	EQU 4
	;[724] CONST PSG_ENVELOPE_CYCLE_RAMP_DOWN_SAWTOOTH			= $08 '\\\\\\CONST PSG_ENVELOPE_CYCLE_RAMP_DOWN_TRIANGLE			= $0A '\/\/\/CONST PSG_ENVELOPE_SINGLE_SHOT_RAMP_DOWN_AND_MAX	= $0B '\^^^^^^
	SRCFILE "constants.bas",724
const_PSG_ENVELOPE_CYCLE_RAMP_DOWN_SAWTOOTH:	EQU 8
	;[725] CONST PSG_ENVELOPE_CYCLE_RAMP_UP_SAWTOOTH			= $0C '///////
	SRCFILE "constants.bas",725
const_PSG_ENVELOPE_CYCLE_RAMP_UP_SAWTOOTH:	EQU 12
	;[726] CONST PSG_ENVELOPE_SINGLE_SHOT_RAMP_UP_AND_MAX		= $0D '/^^^^^^
	SRCFILE "constants.bas",726
const_PSG_ENVELOPE_SINGLE_SHOT_RAMP_UP_AND_MAX:	EQU 13
	;[727] CONST PSG_ENVELOPE_CYCLE_RAMP_UP_TRIANGLE			= $0E '/\/\/\/
	SRCFILE "constants.bas",727
const_PSG_ENVELOPE_CYCLE_RAMP_UP_TRIANGLE:	EQU 14
	;[728] 
	SRCFILE "constants.bas",728
	;[729] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",729
	;[730] 
	SRCFILE "constants.bas",730
	;[731] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",731
	;[732] REM Useful functions.
	SRCFILE "constants.bas",732
	;[733] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",733
	;[734] DEF FN screenpos(aColumn, aRow)				=               (((aRow)*BACKGROUND_COLUMNS)+(aColumn))
	SRCFILE "constants.bas",734
	;[735] DEF FN screenaddr(aColumn, aRow)			= (BACKTAB_ADDR+(((aRow)*BACKGROUND_COLUMNS)+(aColumn)))
	SRCFILE "constants.bas",735
	;[736] 
	SRCFILE "constants.bas",736
	;[737] DEF FN setspritex(aSpriteNo,anXPosition)	= #mobshadow(aSpriteNo  )=(#mobshadow(aSpriteNo  ) and $ff00)+anXPosition
	SRCFILE "constants.bas",737
	;[738] DEF FN setspritey(aSpriteNo,aYPosition)		= #mobshadow(aSpriteNo+8)=(#mobshadow(aSpriteNo+8) and $ff80)+aYPosition
	SRCFILE "constants.bas",738
	;[739] DEF FN resetsprite(aSpriteNo)				= sprite aSpriteNo, 0, 0, 0
	SRCFILE "constants.bas",739
	;[740] DEF FN togglespritevisible(aSpriteNo)		= #mobshadow(aSpriteNo   )=#mobshadow(aSpriteNo)    xor VISIBLE
	SRCFILE "constants.bas",740
	;[741] DEF FN togglespritehit(aSpriteNo)			= #mobshadow(aSpriteNo   )=#mobshadow(aSpriteNo)    xor HIT
	SRCFILE "constants.bas",741
	;[742] DEF FN togglespritebehind(aSpriteNo)		= #mobshadow(aSpriteNo+16)=#mobshadow(aSpriteNo+16) xor BEHIND
	SRCFILE "constants.bas",742
	;[743] 
	SRCFILE "constants.bas",743
	;[744] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "constants.bas",744
	;[745] 
	SRCFILE "constants.bas",745
	;[746] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",746
	;[747] REM END
	SRCFILE "constants.bas",747
	;[748] REM -------------------------------------------------------------------------
	SRCFILE "constants.bas",748
	;ENDFILE
	;FILE pirtoIIDuo.bas
	;[11]     ' Splash screen 
	SRCFILE "pirtoIIDuo.bas",11
	;[12]     INCLUDE "constant2.bas"
	SRCFILE "pirtoIIDuo.bas",12
	;FILE constant2.bas
	;[1] 
	SRCFILE "constant2.bas",1
	;[2] ' =========================================================================
	SRCFILE "constant2.bas",2
	;[3] ' Define Constants
	SRCFILE "constant2.bas",3
	;[4] ' =========================================================================
	SRCFILE "constant2.bas",4
	;[5] CONST TITLE_ROW        = 6      ' Background row in which to print TITLE string
	SRCFILE "constant2.bas",5
const_TITLE_ROW:	EQU 6
	;[6] CONST TITLE_LENGTH     = 13     ' Length of TITLE string, in characters
	SRCFILE "constant2.bas",6
const_TITLE_LENGTH:	EQU 13
	;[7] CONST TITLE_COLOR      = CS_YELLOW  ' Color of TITLE string
	SRCFILE "constant2.bas",7
const_TITLE_COLOR:	EQU 6
	;[8] 
	SRCFILE "constant2.bas",8
	;[9] 
	SRCFILE "constant2.bas",9
	;[10] CONST AUTHOR_ROW       = 10     ' Background row in which to print AUTHOR string
	SRCFILE "constant2.bas",10
const_AUTHOR_ROW:	EQU 10
	;[11] CONST AUTHOR_LENGTH    = 6      ' Length of AUTHOR string, in characters
	SRCFILE "constant2.bas",11
const_AUTHOR_LENGTH:	EQU 6
	;[12] CONST AUTHOR_COLOR     = CS_WHITE   ' Color of AUTHOR string (and copyright year)
	SRCFILE "constant2.bas",12
const_AUTHOR_COLOR:	EQU 7
	;[13] 
	SRCFILE "constant2.bas",13
	;[14] CONST COLOR_BAR_ROW    = 5      ' Background row in which to display colored bars
	SRCFILE "constant2.bas",14
const_COLOR_BAR_ROW:	EQU 5
	;[15] CONST BRAND_ROW        = 3      ' Row in which to print the SDK brand and logo
	SRCFILE "constant2.bas",15
const_BRAND_ROW:	EQU 3
	;[16] CONST BRAND_COLOR      = CS_WHITE   ' Color of SDK brand and logo
	SRCFILE "constant2.bas",16
const_BRAND_COLOR:	EQU 7
	;[17] 
	SRCFILE "constant2.bas",17
	;[18] CONST CARD_WIDTH       = 8      ' Width of a background card, in pixels
	SRCFILE "constant2.bas",18
const_CARD_WIDTH:	EQU 8
	;[19] CONST CARD_HEIGHT      = 8      ' Height of a background card, in pixels
	SRCFILE "constant2.bas",19
const_CARD_HEIGHT:	EQU 8
	;[20] 
	SRCFILE "constant2.bas",20
	;[21] CONST DEBOUNCE_DELAY   = 2      ' Number of cycles to detect button press
	SRCFILE "constant2.bas",21
const_DEBOUNCE_DELAY:	EQU 2
	;[22] CONST NO_KEY           = 0      ' Represents no user input
	SRCFILE "constant2.bas",22
const_NO_KEY:	EQU 0
	;[23]  
	SRCFILE "constant2.bas",23
	;[24] DEF FN TextCenterPos(aLength, aRow)  = SCREENPOS((((BACKGROUND_COLUMNS - aLength) + 1) / 2), aRow)
	SRCFILE "constant2.bas",24
	;[25] DEF FN SpritePosX(aColumn, anOffset) = ((aColumn + 1) * CARD_WIDTH ) + anOffset
	SRCFILE "constant2.bas",25
	;[26] DEF FN SpritePosY(aRow, anOffset)    = ((aRow    + 1) * CARD_HEIGHT) + anOffset
	SRCFILE "constant2.bas",26
	;[27] 
	SRCFILE "constant2.bas",27
	;[28]    ' Set Screen Mode to "Color Stack" and define the stack
	SRCFILE "constant2.bas",28
	;[29]     MODE   SCREEN_COLOR_STACK, STACK_BLACK, STACK_BROWN, STACK_BLACK, STACK_BROWN
	SRCFILE "constant2.bas",29
	MVII #2992,R0
	MVO R0,_color
	MVII #2,R0
	MVO R0,_mode_select
	;[30]     BORDER BORDER_BLACK
	SRCFILE "constant2.bas",30
	CLRR R0
	MVO R0,_border_color
	;[31]     rem DEFINE DEF00,5,Graphics
	SRCFILE "constant2.bas",31
	;[32]     CLS
	SRCFILE "constant2.bas",32
	CALL CLRSCR
	;[33]     DEFINE 0,16,screen_bitmaps_0
	SRCFILE "constant2.bas",33
	CLRR R0
	MVO R0,_gram_target
	MVII #16,R0
	MVO R0,_gram_total
	MVII #label_SCREEN_BITMAPS_0,R0
	MVO R0,_gram_bitmap
	;[34]     WAIT
	SRCFILE "constant2.bas",34
	CALL _wait
	;[35]     DEFINE 16,16,screen_bitmaps_1
	SRCFILE "constant2.bas",35
	MVII #16,R0
	MVO R0,_gram_target
	MVO R0,_gram_total
	MVII #label_SCREEN_BITMAPS_1,R0
	MVO R0,_gram_bitmap
	;[36]    
	SRCFILE "constant2.bas",36
	;[37]     WAIT
	SRCFILE "constant2.bas",37
	CALL _wait
	;[38]     SCREEN screen_cards
	SRCFILE "constant2.bas",38
	MVII #label_SCREEN_CARDS,R3
	MVII #512,R2
	MVII #20,R1
	MVII #12,R0
	CALL CPYBLK
	;[39] 
	SRCFILE "constant2.bas",39
	;[40]       ' Print classic colored bars
	SRCFILE "constant2.bas",40
	;[41]     '  - Vertical bars on left
	SRCFILE "constant2.bas",41
	;[42]     PRINT AT SCREENPOS( 2, COLOR_BAR_ROW) COLOR CS_WHITE,     "\165"
	SRCFILE "constant2.bas",42
	MVII #614,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #1320,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[43]     PRINT AT SCREENPOS( 4, COLOR_BAR_ROW) COLOR CS_YELLOW,    "\165"
	SRCFILE "constant2.bas",43
	MVII #616,R0
	MVO R0,_screen
	MVII #6,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #1320,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[44]     PRINT AT SCREENPOS( 6, COLOR_BAR_ROW) COLOR CS_GREEN,     "\165"
	SRCFILE "constant2.bas",44
	MVII #618,R0
	MVO R0,_screen
	MVII #5,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #1320,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[45]     PRINT AT SCREENPOS( 8, COLOR_BAR_ROW) COLOR CS_DARKGREEN, "\165"
	SRCFILE "constant2.bas",45
	MVII #620,R0
	MVO R0,_screen
	MVII #4,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #1320,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[46]     PRINT AT SCREENPOS( 9, COLOR_BAR_ROW) COLOR CS_RED, "II"
	SRCFILE "constant2.bas",46
	MVII #621,R0
	MVO R0,_screen
	MVII #2,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #328,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO R4,_screen
	;[47]     
	SRCFILE "constant2.bas",47
	;[48]     '  - Vertical bars on right
	SRCFILE "constant2.bas",48
	;[49]     PRINT AT SCREENPOS(11, COLOR_BAR_ROW) COLOR CS_TAN,       "\164"
	SRCFILE "constant2.bas",49
	MVII #623,R0
	MVO R0,_screen
	MVII #3,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #1312,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[50]     PRINT AT SCREENPOS(13, COLOR_BAR_ROW) COLOR CS_RED,       "\164"
	SRCFILE "constant2.bas",50
	MVII #625,R0
	MVO R0,_screen
	MVII #2,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #1312,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[51]     PRINT AT SCREENPOS(15, COLOR_BAR_ROW) COLOR CS_BLUE,      "\164"
	SRCFILE "constant2.bas",51
	MVII #627,R0
	MVO R0,_screen
	MVII #1,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #1312,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[52]     PRINT AT SCREENPOS(17, COLOR_BAR_ROW) COLOR CS_WHITE,     "\164"
	SRCFILE "constant2.bas",52
	MVII #629,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #1312,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[53]     PRINT AT SCREENPOS(48, COLOR_BAR_ROW) COLOR CS_RED, "D U O"
	SRCFILE "constant2.bas",53
	MVII #660,R0
	MVO R0,_screen
	MVII #2,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #288,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #288,R0
	MVO@ R0,R4
	XORI #424,R0
	MVO@ R0,R4
	XORI #424,R0
	MVO@ R0,R4
	XORI #376,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[54] 
	SRCFILE "constant2.bas",54
	;[55] 
	SRCFILE "constant2.bas",55
	;[56]     PRINT AT TextCenterPos((AUTHOR_LENGTH + 4), AUTHOR_ROW) + 0, BG27 + AUTHOR_COLOR
	SRCFILE "constant2.bas",56
	MVII #717,R0
	MVO R0,_screen
	MVII #2271,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	;[57]     PRINT AT TextCenterPos((AUTHOR_LENGTH + 4), AUTHOR_ROW) + 1 COLOR AUTHOR_COLOR,  "2026 AOtta"
	SRCFILE "constant2.bas",57
	MVII #718,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #144,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #16,R0
	MVO@ R0,R4
	XORI #16,R0
	MVO@ R0,R4
	XORI #32,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #264,R0
	MVO@ R0,R4
	XORI #112,R0
	MVO@ R0,R4
	XORI #984,R0
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #168,R0
	MVO@ R0,R4
	MVO R4,_screen
	;ENDFILE
	;FILE pirtoIIDuo.bas
	;[13]     CONST mfile=$817f
	SRCFILE "pirtoIIDuo.bas",13
const_MFILE:	EQU 33151
	;[14]     CONST mst=$813f
	SRCFILE "pirtoIIDuo.bas",14
const_MST:	EQU 33087
	;[15]     const riga=$8899
	SRCFILE "pirtoIIDuo.bas",15
const_RIGA:	EQU 34969
	;[16]     const joy=$8889
	SRCFILE "pirtoIIDuo.bas",16
const_JOY:	EQU 34953
	;[17]     const joyck=$8119
	SRCFILE "pirtoIIDuo.bas",17
const_JOYCK:	EQU 33049
	;[18]     const hack=$9111
	SRCFILE "pirtoIIDuo.bas",18
const_HACK:	EQU 37137
	;[19]     const dirfile=$8651
	SRCFILE "pirtoIIDuo.bas",19
const_DIRFILE:	EQU 34385
	;[20]     const chk=$815e
	SRCFILE "pirtoIIDuo.bas",20
const_CHK:	EQU 33118
	;[21]     const debug=$8163
	SRCFILE "pirtoIIDuo.bas",21
const_DEBUG:	EQU 33123
	;[22]     
	SRCFILE "pirtoIIDuo.bas",22
	;[23] 
	SRCFILE "pirtoIIDuo.bas",23
	;[24]     dim tipo(10)
	SRCFILE "pirtoIIDuo.bas",24
	;[25]     poke(mst),0
	SRCFILE "pirtoIIDuo.bas",25
	CLRR R0
	MVO R0,33087
	;[26]     poke(chk),0
	SRCFILE "pirtoIIDuo.bas",26
	MVO R0,33118
	;[27]     poke(dirfile),0
	SRCFILE "pirtoIIDuo.bas",27
	NOP
	MVO R0,34385
	;[28] 
	SRCFILE "pirtoIIDuo.bas",28
	;[29]    
	SRCFILE "pirtoIIDuo.bas",29
	;[30]     GOSUB reset_sound
	SRCFILE "pirtoIIDuo.bas",30
	CALL label_RESET_SOUND
	;[31]     for A=1 to 2    
	SRCFILE "pirtoIIDuo.bas",31
	MVII #1,R0
	MVO R0,var_A
T1:
	;[32]         IF A=1 THEN #C=477
	SRCFILE "pirtoIIDuo.bas",32
	MVI var_A,R0
	CMPI #1,R0
	BNE T2
	MVII #477,R0
	MVO R0,var_&C
T2:
	;[33]         IF A=2 THEN #C=239
	SRCFILE "pirtoIIDuo.bas",33
	MVI var_A,R0
	CMPI #2,R0
	BNE T3
	MVII #239,R0
	MVO R0,var_&C
T3:
	;[34]     SOUND 0,#C,PSG_ENVELOPE_ENABLE
	SRCFILE "pirtoIIDuo.bas",34
	MVI var_&C,R0
	MVO R0,496
	SWAP R0
	MVO R0,500
	MVII #48,R0
	MVO R0,507
	;[35]     SOUND 1,(#C+1)/2,PSG_ENVELOPE_ENABLE
	SRCFILE "pirtoIIDuo.bas",35
	MVI var_&C,R0
	INCR R0
	SLR R0,1
	MVO R0,497
	SWAP R0
	MVO R0,501
	MVII #48,R0
	MVO R0,508
	;[36]     SOUND 2,#C*2,PSG_ENVELOPE_ENABLE
	SRCFILE "pirtoIIDuo.bas",36
	MVI var_&C,R0
	SLL R0,1
	MVO R0,498
	SWAP R0
	MVO R0,502
	MVII #48,R0
	MVO R0,509
	;[37]     SOUND 3,6000,PSG_ENVELOPE_SINGLE_SHOT_RAMP_DOWN_AND_OFF ' Slow decay, single shot \______
	SRCFILE "pirtoIIDuo.bas",37
	MVII #6000,R0
	MVO R0,499
	SWAP R0
	MVO R0,503
	CLRR R0
	MVO R0,506
	;[38]     FOR C = 1 TO 30:WAIT:NEXT C
	SRCFILE "pirtoIIDuo.bas",38
	MVII #1,R0
	MVO R0,var_C
T4:
	CALL _wait
	MVI var_C,R0
	INCR R0
	MVO R0,var_C
	CMPI #30,R0
	BLE T4
	;[39]     NEXT A
	SRCFILE "pirtoIIDuo.bas",39
	MVI var_A,R0
	INCR R0
	MVO R0,var_A
	CMPI #2,R0
	BLE T1
	;[40]     GOSUB reset_sound
	SRCFILE "pirtoIIDuo.bas",40
	CALL label_RESET_SOUND
	;[41]     poke (joyck),0
	SRCFILE "pirtoIIDuo.bas",41
	CLRR R0
	MVO R0,33049
	;[42]     #cnt=0
	SRCFILE "pirtoIIDuo.bas",42
	MVO R0,var_&CNT
	;[43]     WHILE (cont = NO_KEY) and (peek(joyck)<>123) and (#cnt<100) ' 0x119)  
	SRCFILE "pirtoIIDuo.bas",43
T5:
	MVI 510,R0
	XOR 511,R0
	MVII #65535,R0
	BEQ T7
	INCR R0
T7:
	MVI 33049,R1
	CMPI #123,R1
	MVII #65535,R1
	BNE T8
	INCR R1
T8:
	ANDR R1,R0
	MVI var_&CNT,R1
	CMPI #100,R1
	MVII #65535,R1
	BLT T9
	INCR R1
T9:
	ANDR R1,R0
	BEQ T6
	;[44]         #cnt=#cnt+1
	SRCFILE "pirtoIIDuo.bas",44
	MVI var_&CNT,R0
	INCR R0
	MVO R0,var_&CNT
	;[45]         WAIT
	SRCFILE "pirtoIIDuo.bas",45
	CALL _wait
	;[46]     WEND
	SRCFILE "pirtoIIDuo.bas",46
	B T5
T6:
	;[47]     poke(chk),0
	SRCFILE "pirtoIIDuo.bas",47
	CLRR R0
	MVO R0,33118
	;[48]     WAIT
	SRCFILE "pirtoIIDuo.bas",48
	CALL _wait
	;[49]    
	SRCFILE "pirtoIIDuo.bas",49
	;[50]     poke(joyck),0 '0x119
	SRCFILE "pirtoIIDuo.bas",50
	CLRR R0
	MVO R0,33049
	;[51]     poke (joy),0
	SRCFILE "pirtoIIDuo.bas",51
	MVO R0,34953
	;[52] 
	SRCFILE "pirtoIIDuo.bas",52
	;[53]    ' poke(joy),1 ' carica i file
	SRCFILE "pirtoIIDuo.bas",53
	;[54]   
	SRCFILE "pirtoIIDuo.bas",54
	;[55] avanti:
	SRCFILE "pirtoIIDuo.bas",55
	; AVANTI
label_AVANTI:	;[56]     
	SRCFILE "pirtoIIDuo.bas",56
	;[57]     curriga=0
	SRCFILE "pirtoIIDuo.bas",57
	CLRR R0
	MVO R0,var_CURRIGA
	;[58]     cls     ' Clear the screen.
	SRCFILE "pirtoIIDuo.bas",58
	CALL CLRSCR
	;[59] 
	SRCFILE "pirtoIIDuo.bas",59
	;[60]     wait
	SRCFILE "pirtoIIDuo.bas",60
	CALL _wait
	;[61]     PRINT AT SCREENPOS(1, 0) COLOR CS_RED,"PiRTO II-2"
	SRCFILE "pirtoIIDuo.bas",61
	MVII #513,R0
	MVO R0,_screen
	MVII #2,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #384,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #968,R0
	MVO@ R0,R4
	XORI #984,R0
	MVO@ R0,R4
	XORI #48,R0
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	XORI #376,R0
	MVO@ R0,R4
	XORI #328,R0
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #288,R0
	MVO@ R0,R4
	XORI #248,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[62]     PRINT COLOR CS_WHITE," - SDCard"
	SRCFILE "pirtoIIDuo.bas",62
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVO@ R0,R4
	XORI #104,R0
	MVO@ R0,R4
	XORI #104,R0
	MVO@ R0,R4
	XORI #408,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #784,R0
	MVO@ R0,R4
	XORI #152,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[63]     PRINT AT SCREENPOS(0, 11) COLOR CS_WHITE,"ENT/BT:sel*CLR:../"
	SRCFILE "pirtoIIDuo.bas",63
	MVII #732,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #296,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #88,R0
	MVO@ R0,R4
	XORI #208,R0
	MVO@ R0,R4
	XORI #472,R0
	MVO@ R0,R4
	XORI #360,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #368,R0
	MVO@ R0,R4
	XORI #584,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #560,R0
	MVO@ R0,R4
	XORI #328,R0
	MVO@ R0,R4
	XORI #120,R0
	MVO@ R0,R4
	XORI #240,R0
	MVO@ R0,R4
	XORI #320,R0
	MVO@ R0,R4
	XORI #160,R0
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #8,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[64]     
	SRCFILE "pirtoIIDuo.bas",64
	;[65]    
	SRCFILE "pirtoIIDuo.bas",65
	;[66]       
	SRCFILE "pirtoIIDuo.bas",66
	;[67] menu:
	SRCFILE "pirtoIIDuo.bas",67
	; MENU
label_MENU:	;[68]     GOSUB leggimenu
	SRCFILE "pirtoIIDuo.bas",68
	CALL label_LEGGIMENU
	;[69]     c = cont
	SRCFILE "pirtoIIDuo.bas",69
	MVI 510,R0
	XOR 511,R0
	MVO R0,var_C
	;[70]     
	SRCFILE "pirtoIIDuo.bas",70
	;[71]     if (c=KEYPAD_ENTER) or (c=BUTTON_1) or (c=BUTTON_2) or (c=BUTTON_3) then 
	SRCFILE "pirtoIIDuo.bas",71
	MVI var_C,R0
	CMPI #40,R0
	MVII #65535,R0
	BEQ T11
	INCR R0
T11:
	MVI var_C,R1
	CMPI #160,R1
	MVII #65535,R1
	BEQ T12
	INCR R1
T12:
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	MVI var_C,R1
	CMPI #96,R1
	MVII #65535,R1
	BEQ T13
	INCR R1
T13:
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	MVI var_C,R1
	CMPI #192,R1
	MVII #65535,R1
	BEQ T14
	INCR R1
T14:
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	BEQ T10
	;[72]         poke(joy),0:poke(joyck),0
	SRCFILE "pirtoIIDuo.bas",72
	CLRR R0
	MVO R0,34953
	MVO R0,33049
	;[73]         goto select
	SRCFILE "pirtoIIDuo.bas",73
	B label_SELECT
	;[74]     end if
	SRCFILE "pirtoIIDuo.bas",74
T10:
	;[75] 
	SRCFILE "pirtoIIDuo.bas",75
	;[76]     if (c=KEYPAD_CLEAR) then
	SRCFILE "pirtoIIDuo.bas",76
	MVI var_C,R0
	CMPI #136,R0
	BNE T15
	;[77]         sound 0,120,15
	SRCFILE "pirtoIIDuo.bas",77
	MVII #120,R0
	MVO R0,496
	SWAP R0
	MVO R0,500
	MVII #15,R0
	MVO R0,507
	;[78]         for p=0 to 5:next p
	SRCFILE "pirtoIIDuo.bas",78
	CLRR R0
	MVO R0,var_P
T16:
	MVI var_P,R0
	INCR R0
	MVO R0,var_P
	CMPI #5,R0
	BLE T16
	;[79]         sound 0,0,0 
	SRCFILE "pirtoIIDuo.bas",79
	CLRR R0
	MVO R0,496
	SWAP R0
	MVO R0,500
	CLRR R0
	MVO R0,507
	;[80]         cls
	SRCFILE "pirtoIIDuo.bas",80
	CALL CLRSCR
	;[81]         k=0
	SRCFILE "pirtoIIDuo.bas",81
	CLRR R0
	MVO R0,var_K
	;[82]         while peek(joyck)<>1 'and #cnt<500' 0x119
	SRCFILE "pirtoIIDuo.bas",82
T17:
	MVI 33049,R0
	CMPI #1,R0
	BEQ T18
	;[83]             poke(joy),5
	SRCFILE "pirtoIIDuo.bas",83
	MVII #5,R0
	MVO R0,34953
	;[84]             print at screenpos(3,2) color CS_TAN,"UP DIR" ' root
	SRCFILE "pirtoIIDuo.bas",84
	MVII #555,R0
	MVO R0,_screen
	MVII #3,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #424,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #40,R0
	MVO@ R0,R4
	XORI #384,R0
	MVO@ R0,R4
	XORI #288,R0
	MVO@ R0,R4
	XORI #104,R0
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[85]             print at screenpos(3,5),"PLEASE WAIT..."
	SRCFILE "pirtoIIDuo.bas",85
	MVII #615,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #384,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #32,R0
	MVO@ R0,R4
	XORI #144,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #296,R0
	MVO@ R0,R4
	XORI #440,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #64,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #464,R0
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO R4,_screen
	;[86]             if k=0 then print at screenpos(10,8),BG28 + CS_BLUE
	SRCFILE "pirtoIIDuo.bas",86
	MVI var_K,R0
	TSTR R0
	BNE T19
	MVII #682,R0
	MVO R0,_screen
	MVII #2273,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T19:
	;[87]             if k=1 then print at screenpos(10,8),BG29 + CS_BLUE
	SRCFILE "pirtoIIDuo.bas",87
	MVI var_K,R0
	CMPI #1,R0
	BNE T20
	MVII #682,R0
	MVO R0,_screen
	MVII #2281,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T20:
	;[88]             if k=2 then print at screenpos(10,8),BG30 + CS_BLUE
	SRCFILE "pirtoIIDuo.bas",88
	MVI var_K,R0
	CMPI #2,R0
	BNE T21
	MVII #682,R0
	MVO R0,_screen
	MVII #2289,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T21:
	;[89]             if k=3 then print at screenpos(10,8),BG31 + CS_BLUE
	SRCFILE "pirtoIIDuo.bas",89
	MVI var_K,R0
	CMPI #3,R0
	BNE T22
	MVII #682,R0
	MVO R0,_screen
	MVII #2297,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T22:
	;[90]             k=k+1:#cnt=#cnt+1
	SRCFILE "pirtoIIDuo.bas",90
	MVI var_K,R0
	INCR R0
	MVO R0,var_K
	MVI var_&CNT,R0
	INCR R0
	MVO R0,var_&CNT
	;[91]             if k>3 then k=0   
	SRCFILE "pirtoIIDuo.bas",91
	MVI var_K,R0
	CMPI #3,R0
	BLE T23
	CLRR R0
	MVO R0,var_K
T23:
	;[92]         wend
	SRCFILE "pirtoIIDuo.bas",92
	B T17
T18:
	;[93]         
	SRCFILE "pirtoIIDuo.bas",93
	;[94]         poke(joyck),0
	SRCFILE "pirtoIIDuo.bas",94
	CLRR R0
	MVO R0,33049
	;[95]         poke (joy),0  
	SRCFILE "pirtoIIDuo.bas",95
	MVO R0,34953
	;[96]         goto avanti
	SRCFILE "pirtoIIDuo.bas",96
	B label_AVANTI
	;[97]     end if    
	SRCFILE "pirtoIIDuo.bas",97
T15:
	;[98] 
	SRCFILE "pirtoIIDuo.bas",98
	;[99]     if cont.down and (curriga<lastriga) then
	SRCFILE "pirtoIIDuo.bas",99
	MVI 510,R0
	XOR 511,R0
	ANDI #1,R0
	MVI var_CURRIGA,R1
	CMP var_LASTRIGA,R1
	MVII #65535,R1
	BLT T25
	INCR R1
T25:
	ANDR R1,R0
	BEQ T24
	;[100]        curriga=curriga+1 ' giù
	SRCFILE "pirtoIIDuo.bas",100
	MVI var_CURRIGA,R0
	INCR R0
	MVO R0,var_CURRIGA
	;[101]        sound 0,140,15
	SRCFILE "pirtoIIDuo.bas",101
	MVII #140,R0
	MVO R0,496
	SWAP R0
	MVO R0,500
	MVII #15,R0
	MVO R0,507
	;[102]        for p=0 to 9:next p
	SRCFILE "pirtoIIDuo.bas",102
	CLRR R0
	MVO R0,var_P
T26:
	MVI var_P,R0
	INCR R0
	MVO R0,var_P
	CMPI #9,R0
	BLE T26
	;[103]        wait
	SRCFILE "pirtoIIDuo.bas",103
	CALL _wait
	;[104]        sound 0,0,0 
	SRCFILE "pirtoIIDuo.bas",104
	CLRR R0
	MVO R0,496
	SWAP R0
	MVO R0,500
	CLRR R0
	MVO R0,507
	;[105]     end if
	SRCFILE "pirtoIIDuo.bas",105
T24:
	;[106]     
	SRCFILE "pirtoIIDuo.bas",106
	;[107]     if cont.up and curriga>0 then 
	SRCFILE "pirtoIIDuo.bas",107
	MVI 510,R0
	XOR 511,R0
	ANDI #4,R0
	MVI var_CURRIGA,R1
	CMPI #0,R1
	MVII #65535,R1
	BGT T28
	INCR R1
T28:
	ANDR R1,R0
	BEQ T27
	;[108]        curriga=curriga-1 ' su
	SRCFILE "pirtoIIDuo.bas",108
	MVI var_CURRIGA,R0
	DECR R0
	MVO R0,var_CURRIGA
	;[109]        sound 0,140,15
	SRCFILE "pirtoIIDuo.bas",109
	MVII #140,R0
	MVO R0,496
	SWAP R0
	MVO R0,500
	MVII #15,R0
	MVO R0,507
	;[110]        for p=0 to 9:next p
	SRCFILE "pirtoIIDuo.bas",110
	CLRR R0
	MVO R0,var_P
T29:
	MVI var_P,R0
	INCR R0
	MVO R0,var_P
	CMPI #9,R0
	BLE T29
	;[111]        wait
	SRCFILE "pirtoIIDuo.bas",111
	CALL _wait
	;[112]        sound 0,0,0 
	SRCFILE "pirtoIIDuo.bas",112
	CLRR R0
	MVO R0,496
	SWAP R0
	MVO R0,500
	CLRR R0
	MVO R0,507
	;[113]     end if
	SRCFILE "pirtoIIDuo.bas",113
T27:
	;[114]     if cont.right then 
	SRCFILE "pirtoIIDuo.bas",114
	MVI 510,R0
	XOR 511,R0
	ANDI #2,R0
	BEQ T30
	;[115]         sound 0,140,15
	SRCFILE "pirtoIIDuo.bas",115
	MVII #140,R0
	MVO R0,496
	SWAP R0
	MVO R0,500
	MVII #15,R0
	MVO R0,507
	;[116]         sound 0,0,0 
	SRCFILE "pirtoIIDuo.bas",116
	CLRR R0
	MVO R0,496
	SWAP R0
	MVO R0,500
	CLRR R0
	MVO R0,507
	;[117]         k=0:#cnt=0
	SRCFILE "pirtoIIDuo.bas",117
	MVO R0,var_K
	NOP
	MVO R0,var_&CNT
	;[118]         cls
	SRCFILE "pirtoIIDuo.bas",118
	CALL CLRSCR
	;[119]         print at screenpos(3,2) color CS_TAN,"Loading next page" ' root
	SRCFILE "pirtoIIDuo.bas",119
	MVII #555,R0
	MVO R0,_screen
	MVII #3,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #352,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #792,R0
	MVO@ R0,R4
	XORI #112,R0
	MVO@ R0,R4
	XORI #40,R0
	MVO@ R0,R4
	XORI #104,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #568,R0
	MVO@ R0,R4
	XORI #624,R0
	MVO@ R0,R4
	XORI #88,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #96,R0
	MVO@ R0,R4
	XORI #672,R0
	MVO@ R0,R4
	XORI #640,R0
	MVO@ R0,R4
	XORI #136,R0
	MVO@ R0,R4
	XORI #48,R0
	MVO@ R0,R4
	XORI #16,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[120]         print at screenpos(3,5),"Please wait..."
	SRCFILE "pirtoIIDuo.bas",120
	MVII #615,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #384,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #992,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #32,R0
	MVO@ R0,R4
	XORI #144,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #552,R0
	MVO@ R0,R4
	XORI #696,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #64,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #720,R0
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO R4,_screen
	;[121]         poke (joy),3
	SRCFILE "pirtoIIDuo.bas",121
	MVII #3,R0
	MVO R0,34953
	;[122]         while peek(joyck)<>1 'and #cnt<500 ' 0x119
	SRCFILE "pirtoIIDuo.bas",122
T31:
	MVI 33049,R0
	CMPI #1,R0
	BEQ T32
	;[123]             if k=0 then print at screenpos(10,8),BG28 + CS_BLUE
	SRCFILE "pirtoIIDuo.bas",123
	MVI var_K,R0
	TSTR R0
	BNE T33
	MVII #682,R0
	MVO R0,_screen
	MVII #2273,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T33:
	;[124]             if k=1 then print at screenpos(10,8),BG29 + CS_BLUE
	SRCFILE "pirtoIIDuo.bas",124
	MVI var_K,R0
	CMPI #1,R0
	BNE T34
	MVII #682,R0
	MVO R0,_screen
	MVII #2281,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T34:
	;[125]             if k=2 then print at screenpos(10,8),BG30 + CS_BLUE
	SRCFILE "pirtoIIDuo.bas",125
	MVI var_K,R0
	CMPI #2,R0
	BNE T35
	MVII #682,R0
	MVO R0,_screen
	MVII #2289,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T35:
	;[126]             if k=3 then print at screenpos(10,8),BG31 + CS_BLUE    
	SRCFILE "pirtoIIDuo.bas",126
	MVI var_K,R0
	CMPI #3,R0
	BNE T36
	MVII #682,R0
	MVO R0,_screen
	MVII #2297,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T36:
	;[127]             k=k+1:#cnt=#cnt+1
	SRCFILE "pirtoIIDuo.bas",127
	MVI var_K,R0
	INCR R0
	MVO R0,var_K
	MVI var_&CNT,R0
	INCR R0
	MVO R0,var_&CNT
	;[128]             if k>3 then k=0
	SRCFILE "pirtoIIDuo.bas",128
	MVI var_K,R0
	CMPI #3,R0
	BLE T37
	CLRR R0
	MVO R0,var_K
T37:
	;[129]             poke(joy),3
	SRCFILE "pirtoIIDuo.bas",129
	MVII #3,R0
	MVO R0,34953
	;[130]         wend
	SRCFILE "pirtoIIDuo.bas",130
	B T31
T32:
	;[131]         poke(joyck),0 '0x119
	SRCFILE "pirtoIIDuo.bas",131
	CLRR R0
	MVO R0,33049
	;[132]         poke (joy),0
	SRCFILE "pirtoIIDuo.bas",132
	MVO R0,34953
	;[133]         goto avanti
	SRCFILE "pirtoIIDuo.bas",133
	B label_AVANTI
	;[134]     end if
	SRCFILE "pirtoIIDuo.bas",134
T30:
	;[135]     if cont.left then 
	SRCFILE "pirtoIIDuo.bas",135
	MVI 510,R0
	XOR 511,R0
	ANDI #8,R0
	BEQ T38
	;[136]         sound 0,120,15
	SRCFILE "pirtoIIDuo.bas",136
	MVII #120,R0
	MVO R0,496
	SWAP R0
	MVO R0,500
	MVII #15,R0
	MVO R0,507
	;[137]         for p=0 to 9:next p
	SRCFILE "pirtoIIDuo.bas",137
	CLRR R0
	MVO R0,var_P
T39:
	MVI var_P,R0
	INCR R0
	MVO R0,var_P
	CMPI #9,R0
	BLE T39
	;[138]         wait
	SRCFILE "pirtoIIDuo.bas",138
	CALL _wait
	;[139]         sound 0,0,0 
	SRCFILE "pirtoIIDuo.bas",139
	CLRR R0
	MVO R0,496
	SWAP R0
	MVO R0,500
	CLRR R0
	MVO R0,507
	;[140]         k=0:#cnt=0
	SRCFILE "pirtoIIDuo.bas",140
	MVO R0,var_K
	NOP
	MVO R0,var_&CNT
	;[141]         cls
	SRCFILE "pirtoIIDuo.bas",141
	CALL CLRSCR
	;[142]         print at screenpos(3,2) color CS_TAN,"Prev DIR" ' root
	SRCFILE "pirtoIIDuo.bas",142
	MVII #555,R0
	MVO R0,_screen
	MVII #3,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #384,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #784,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #152,R0
	MVO@ R0,R4
	XORI #688,R0
	MVO@ R0,R4
	XORI #288,R0
	MVO@ R0,R4
	XORI #104,R0
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[143]         print at screenpos(3,5),"Please wait..."
	SRCFILE "pirtoIIDuo.bas",143
	MVII #615,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #384,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #992,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #32,R0
	MVO@ R0,R4
	XORI #144,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #552,R0
	MVO@ R0,R4
	XORI #696,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #64,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #720,R0
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO R4,_screen
	;[144]         poke(joy),4
	SRCFILE "pirtoIIDuo.bas",144
	MVII #4,R0
	MVO R0,34953
	;[145]         while peek(joyck)<>1 'and #cnt<500 ' 0x119
	SRCFILE "pirtoIIDuo.bas",145
T40:
	MVI 33049,R0
	CMPI #1,R0
	BEQ T41
	;[146]             if k=0 then print at screenpos(10,8),BG28 + CS_BLUE
	SRCFILE "pirtoIIDuo.bas",146
	MVI var_K,R0
	TSTR R0
	BNE T42
	MVII #682,R0
	MVO R0,_screen
	MVII #2273,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T42:
	;[147]             if k=1 then print at screenpos(10,8),BG29 + CS_BLUE
	SRCFILE "pirtoIIDuo.bas",147
	MVI var_K,R0
	CMPI #1,R0
	BNE T43
	MVII #682,R0
	MVO R0,_screen
	MVII #2281,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T43:
	;[148]             if k=2 then print at screenpos(10,8),BG30 + CS_BLUE
	SRCFILE "pirtoIIDuo.bas",148
	MVI var_K,R0
	CMPI #2,R0
	BNE T44
	MVII #682,R0
	MVO R0,_screen
	MVII #2289,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T44:
	;[149]             if k=3 then print at screenpos(10,8),BG31 + CS_BLUE
	SRCFILE "pirtoIIDuo.bas",149
	MVI var_K,R0
	CMPI #3,R0
	BNE T45
	MVII #682,R0
	MVO R0,_screen
	MVII #2297,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T45:
	;[150]             k=k+1:#cnt=#cnt+1
	SRCFILE "pirtoIIDuo.bas",150
	MVI var_K,R0
	INCR R0
	MVO R0,var_K
	MVI var_&CNT,R0
	INCR R0
	MVO R0,var_&CNT
	;[151]             if k>3 then k=0
	SRCFILE "pirtoIIDuo.bas",151
	MVI var_K,R0
	CMPI #3,R0
	BLE T46
	CLRR R0
	MVO R0,var_K
T46:
	;[152]             poke(joy),4
	SRCFILE "pirtoIIDuo.bas",152
	MVII #4,R0
	MVO R0,34953
	;[153]         wend
	SRCFILE "pirtoIIDuo.bas",153
	B T40
T41:
	;[154]         poke(joyck),0
	SRCFILE "pirtoIIDuo.bas",154
	CLRR R0
	MVO R0,33049
	;[155]         poke (joy),0  
	SRCFILE "pirtoIIDuo.bas",155
	MVO R0,34953
	;[156]         goto avanti
	SRCFILE "pirtoIIDuo.bas",156
	B label_AVANTI
	;[157]     end if
	SRCFILE "pirtoIIDuo.bas",157
T38:
	;[158] 
	SRCFILE "pirtoIIDuo.bas",158
	;[159] 
	SRCFILE "pirtoIIDuo.bas",159
	;[160]     goto menu
	SRCFILE "pirtoIIDuo.bas",160
	B label_MENU
	;[161]    
	SRCFILE "pirtoIIDuo.bas",161
	;[162] select:
	SRCFILE "pirtoIIDuo.bas",162
	; SELECT
label_SELECT:	;[163]     k=0
	SRCFILE "pirtoIIDuo.bas",163
	CLRR R0
	MVO R0,var_K
	;[164]     CLS
	SRCFILE "pirtoIIDuo.bas",164
	CALL CLRSCR
	;[165]     print at screenpos(3,2) color CS_TAN," LOADING" ' root
	SRCFILE "pirtoIIDuo.bas",165
	MVII #555,R0
	MVO R0,_screen
	MVII #3,R0
	MVO R0,_color
	MVI _screen,R4
	MVO@ R0,R4
	XORI #352,R0
	MVO@ R0,R4
	XORI #24,R0
	MVO@ R0,R4
	XORI #112,R0
	MVO@ R0,R4
	XORI #40,R0
	MVO@ R0,R4
	XORI #104,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[166]     print at screenpos(3,5),"PLEASE WAIT..."
	SRCFILE "pirtoIIDuo.bas",166
	MVII #615,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #384,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #32,R0
	MVO@ R0,R4
	XORI #144,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #296,R0
	MVO@ R0,R4
	XORI #440,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #64,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #464,R0
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO R4,_screen
	;[167]     'print at screenpos(3,6),<1>tipo(curriga)
	SRCFILE "pirtoIIDuo.bas",167
	;[168]     
	SRCFILE "pirtoIIDuo.bas",168
	;[169]     poke(riga),curriga+1      
	SRCFILE "pirtoIIDuo.bas",169
	MVI var_CURRIGA,R0
	INCR R0
	MVO R0,34969
	;[170]     poke(joy),2
	SRCFILE "pirtoIIDuo.bas",170
	MVII #2,R0
	MVO R0,34953
	;[171] 'poivia ---------------------------------------------------
	SRCFILE "pirtoIIDuo.bas",171
	;[172]     if peek(debug)>1 then gosub debug
	SRCFILE "pirtoIIDuo.bas",172
	MVI 33123,R0
	CMPI #1,R0
	BLE T47
	CALL label_DEBUG
T47:
	;[173] 
	SRCFILE "pirtoIIDuo.bas",173
	;[174]     while peek(joyck)<>1 'and #cnt<500' 0x119
	SRCFILE "pirtoIIDuo.bas",174
T48:
	MVI 33049,R0
	CMPI #1,R0
	BEQ T49
	;[175]         if k=0 then print at screenpos(10,8),BG28 + CS_BLUE
	SRCFILE "pirtoIIDuo.bas",175
	MVI var_K,R0
	TSTR R0
	BNE T50
	MVII #682,R0
	MVO R0,_screen
	MVII #2273,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T50:
	;[176]         if k=1 then print at screenpos(10,8),BG29 + CS_BLUE
	SRCFILE "pirtoIIDuo.bas",176
	MVI var_K,R0
	CMPI #1,R0
	BNE T51
	MVII #682,R0
	MVO R0,_screen
	MVII #2281,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T51:
	;[177]         if k=2 then print at screenpos(10,8),BG30 + CS_BLUE
	SRCFILE "pirtoIIDuo.bas",177
	MVI var_K,R0
	CMPI #2,R0
	BNE T52
	MVII #682,R0
	MVO R0,_screen
	MVII #2289,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T52:
	;[178]         if k=3 then print at screenpos(10,8),BG31 + CS_BLUE
	SRCFILE "pirtoIIDuo.bas",178
	MVI var_K,R0
	CMPI #3,R0
	BNE T53
	MVII #682,R0
	MVO R0,_screen
	MVII #2297,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T53:
	;[179]     
	SRCFILE "pirtoIIDuo.bas",179
	;[180]         k=k+1:#cnt=#cnt+1
	SRCFILE "pirtoIIDuo.bas",180
	MVI var_K,R0
	INCR R0
	MVO R0,var_K
	MVI var_&CNT,R0
	INCR R0
	MVO R0,var_&CNT
	;[181]         if k>3 then k=0
	SRCFILE "pirtoIIDuo.bas",181
	MVI var_K,R0
	CMPI #3,R0
	BLE T54
	CLRR R0
	MVO R0,var_K
T54:
	;[182]  
	SRCFILE "pirtoIIDuo.bas",182
	;[183]     wend
	SRCFILE "pirtoIIDuo.bas",183
	B T48
T49:
	;[184]     poke(joyck),0
	SRCFILE "pirtoIIDuo.bas",184
	CLRR R0
	MVO R0,33049
	;[185]     poke (joy),0  
	SRCFILE "pirtoIIDuo.bas",185
	MVO R0,34953
	;[186]     if tipo(curriga)=2 then goto avanti ' directory
	SRCFILE "pirtoIIDuo.bas",186
	MVII #array_TIPO,R3
	ADD var_CURRIGA,R3
	MVI@ R3,R0
	CMPI #2,R0
	BEQ label_AVANTI
	;[187]     'goto avanti    
	SRCFILE "pirtoIIDuo.bas",187
	;[188] ' sennò è Gioco
	SRCFILE "pirtoIIDuo.bas",188
	;[189]     cls
	SRCFILE "pirtoIIDuo.bas",189
	CALL CLRSCR
	;[190]     print at screenpos(3,2) color CS_TAN," LOADING GAME" ' root
	SRCFILE "pirtoIIDuo.bas",190
	MVII #555,R0
	MVO R0,_screen
	MVII #3,R0
	MVO R0,_color
	MVI _screen,R4
	MVO@ R0,R4
	XORI #352,R0
	MVO@ R0,R4
	XORI #24,R0
	MVO@ R0,R4
	XORI #112,R0
	MVO@ R0,R4
	XORI #40,R0
	MVO@ R0,R4
	XORI #104,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #312,R0
	MVO@ R0,R4
	XORI #312,R0
	MVO@ R0,R4
	XORI #48,R0
	MVO@ R0,R4
	XORI #96,R0
	MVO@ R0,R4
	XORI #64,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[191]     print at screenpos(3,5),"PLEASE WAIT..."
	SRCFILE "pirtoIIDuo.bas",191
	MVII #615,R0
	MVO R0,_screen
	MOVR R0,R4
	MVII #384,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #72,R0
	MVO@ R0,R4
	XORI #32,R0
	MVO@ R0,R4
	XORI #144,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #296,R0
	MVO@ R0,R4
	XORI #440,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #64,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #464,R0
	MVO@ R0,R4
	MVO@ R0,R4
	MVO@ R0,R4
	NOP
	MVO R4,_screen
	;[192]     '  print at screenpos(3,6),<1>tipo(curriga)
	SRCFILE "pirtoIIDuo.bas",192
	;[193] 
	SRCFILE "pirtoIIDuo.bas",193
	;[194] fine:
	SRCFILE "pirtoIIDuo.bas",194
	; FINE
label_FINE:	;[195]     goto fine
	SRCFILE "pirtoIIDuo.bas",195
	B label_FINE
	;[196] 
	SRCFILE "pirtoIIDuo.bas",196
	;[197] leggimenu: PROCEDURE
	SRCFILE "pirtoIIDuo.bas",197
	; LEGGIMENU
label_LEGGIMENU:	PROC
	BEGIN
	;[198]     lastriga=0
	SRCFILE "pirtoIIDuo.bas",198
	CLRR R0
	MVO R0,var_LASTRIGA
	;[199]     emptylines=0
	SRCFILE "pirtoIIDuo.bas",199
	MVO R0,var_EMPTYLINES
	;[200]     for j=0 to 9
	SRCFILE "pirtoIIDuo.bas",200
	NOP
	MVO R0,var_J
T56:
	;[201]         lastriga=lastriga+1
	SRCFILE "pirtoIIDuo.bas",201
	MVI var_LASTRIGA,R0
	INCR R0
	MVO R0,var_LASTRIGA
	;[202]         for i=0 to 19
	SRCFILE "pirtoIIDuo.bas",202
	CLRR R0
	MVO R0,var_I
T57:
	;[203]          
	SRCFILE "pirtoIIDuo.bas",203
	;[204]             #mem=peek((mfile+i*2)+40*j)
	SRCFILE "pirtoIIDuo.bas",204
	MVI var_I,R1
	SLL R1,1
	ADDI #33151,R1
	MVI var_J,R2
	MULT R2,R4,40
	ADDR R2,R1
	MVI@ R1,R0
	MVO R0,var_&MEM
	;[205]             if i=0 and #mem=0 then ' empty line
	SRCFILE "pirtoIIDuo.bas",205
	MVI var_I,R0
	TSTR R0
	MVII #65535,R0
	BEQ T59
	INCR R0
T59:
	MVI var_&MEM,R1
	TSTR R1
	MVII #65535,R1
	BEQ T60
	INCR R1
T60:
	ANDR R1,R0
	BEQ T58
	;[206]                 #mem=32
	SRCFILE "pirtoIIDuo.bas",206
	MVII #32,R0
	MVO R0,var_&MEM
	;[207]                 emptylines=emptylines+1
	SRCFILE "pirtoIIDuo.bas",207
	MVI var_EMPTYLINES,R0
	INCR R0
	MVO R0,var_EMPTYLINES
	;[208]                 tipo(j)=0
	SRCFILE "pirtoIIDuo.bas",208
	CLRR R0
	MVII #array_TIPO,R3
	ADD var_J,R3
	MVO@ R0,R3
	;[209]             end if 
	SRCFILE "pirtoIIDuo.bas",209
T58:
	;[210]             if j=curriga then 
	SRCFILE "pirtoIIDuo.bas",210
	MVI var_J,R0
	CMP var_CURRIGA,R0
	BNE T61
	;[211]                 if peek($9000+j)=1 then 
	SRCFILE "pirtoIIDuo.bas",211
	MOVR R0,R1
	ADDI #36864,R1
	MVI@ R1,R0
	CMPI #1,R0
	BNE T62
	;[212]                     tipo(j)=2 'dir
	SRCFILE "pirtoIIDuo.bas",212
	MVII #2,R0
	MVII #array_TIPO,R3
	ADD var_J,R3
	MVO@ R0,R3
	;[213]                 else
	SRCFILE "pirtoIIDuo.bas",213
	B T63
T62:
	;[214]                     tipo(j)=1 'file
	SRCFILE "pirtoIIDuo.bas",214
	MVII #1,R0
	MVII #array_TIPO,R3
	ADD var_J,R3
	MVO@ R0,R3
	;[215]                 end if
	SRCFILE "pirtoIIDuo.bas",215
T63:
	;[216]                 if #mem<32 then #mem=32
	SRCFILE "pirtoIIDuo.bas",216
	MVI var_&MEM,R0
	CMPI #32,R0
	BGE T64
	MVII #32,R0
	MVO R0,var_&MEM
T64:
	;[217]                 PRINT AT screenpos(i,j+1),(#mem-32)*8+CS_YELLOW
	SRCFILE "pirtoIIDuo.bas",217
	MVI var_J,R0
	INCR R0
	MULT R0,R4,20
	ADD var_I,R0
	ADDI #512,R0
	MVO R0,_screen
	MVI var_&MEM,R0
	SUBI #32,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #6,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	;[218]             else
	SRCFILE "pirtoIIDuo.bas",218
	B T65
T61:
	;[219]                 if peek($9000+j)=1 then
	SRCFILE "pirtoIIDuo.bas",219
	MVI var_J,R1
	ADDI #36864,R1
	MVI@ R1,R0
	CMPI #1,R0
	BNE T66
	;[220]                     tipo(j)=2 'dir
	SRCFILE "pirtoIIDuo.bas",220
	MVII #2,R0
	MVII #array_TIPO,R3
	ADD var_J,R3
	MVO@ R0,R3
	;[221]                     if #mem<32 then #mem=32
	SRCFILE "pirtoIIDuo.bas",221
	MVI var_&MEM,R0
	CMPI #32,R0
	BGE T67
	MVII #32,R0
	MVO R0,var_&MEM
T67:
	;[222]                     PRINT AT screenpos(i,j+1), (#mem-32)*8+CS_BLUE
	SRCFILE "pirtoIIDuo.bas",222
	MVI var_J,R0
	INCR R0
	MULT R0,R4,20
	ADD var_I,R0
	ADDI #512,R0
	MVO R0,_screen
	MVI var_&MEM,R0
	SUBI #32,R0
	SLL R0,2
	ADDR R0,R0
	INCR R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	;[223]                 else
	SRCFILE "pirtoIIDuo.bas",223
	B T68
T66:
	;[224]                     tipo(j)=1
	SRCFILE "pirtoIIDuo.bas",224
	MVII #1,R0
	MVII #array_TIPO,R3
	ADD var_J,R3
	MVO@ R0,R3
	;[225]                     if #mem<32 then #mem=32
	SRCFILE "pirtoIIDuo.bas",225
	MVI var_&MEM,R0
	CMPI #32,R0
	BGE T69
	MVII #32,R0
	MVO R0,var_&MEM
T69:
	;[226]                     PRINT AT screenpos(i,j+1), (#mem-32)*8+CS_GREEN
	SRCFILE "pirtoIIDuo.bas",226
	MVI var_J,R0
	INCR R0
	MULT R0,R4,20
	ADD var_I,R0
	ADDI #512,R0
	MVO R0,_screen
	MVI var_&MEM,R0
	SUBI #32,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #5,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	;[227]                 end if  
	SRCFILE "pirtoIIDuo.bas",227
T68:
	;[228]             end if
	SRCFILE "pirtoIIDuo.bas",228
T65:
	;[229]          
	SRCFILE "pirtoIIDuo.bas",229
	;[230]         next i
	SRCFILE "pirtoIIDuo.bas",230
	MVI var_I,R0
	INCR R0
	MVO R0,var_I
	CMPI #19,R0
	BLE T57
	;[231]     next j
	SRCFILE "pirtoIIDuo.bas",231
	MVI var_J,R0
	INCR R0
	MVO R0,var_J
	CMPI #9,R0
	BLE T56
	;[232]     lastriga=lastriga-emptylines-1
	SRCFILE "pirtoIIDuo.bas",232
	MVI var_LASTRIGA,R0
	SUB var_EMPTYLINES,R0
	DECR R0
	MVO R0,var_LASTRIGA
	;[233] if peek(debug)>0 then
	SRCFILE "pirtoIIDuo.bas",233
	MVI 33123,R0
	CMPI #0,R0
	BLE T70
	;[234]     print at screenpos(0,11),<2>lastriga
	SRCFILE "pirtoIIDuo.bas",234
	MVII #732,R0
	MVO R0,_screen
	MVI var_LASTRIGA,R0
	MVII #2,R2
	MVI _color,R3
	MVI _screen,R4
	CALL PRNUM16.z
	MVO R4,_screen
	;[235]     print at screenpos(17,11),<2>emptylines
	SRCFILE "pirtoIIDuo.bas",235
	MVII #749,R0
	MVO R0,_screen
	MVI var_EMPTYLINES,R0
	MVII #2,R2
	MVI _color,R3
	MVI _screen,R4
	CALL PRNUM16.z
	MVO R4,_screen
	;[236]     print at screenpos(8,11),<2>curriga
	SRCFILE "pirtoIIDuo.bas",236
	MVII #740,R0
	MVO R0,_screen
	MVI var_CURRIGA,R0
	MVII #2,R2
	MVI _color,R3
	MVI _screen,R4
	CALL PRNUM16.z
	MVO R4,_screen
	;[237]     print at screenpos(0,11),<3>peek($8000+$1030)
	SRCFILE "pirtoIIDuo.bas",237
	MVII #732,R0
	MVO R0,_screen
	MVI 36912,R0
	MVII #3,R2
	MVI _color,R3
	MVI _screen,R4
	CALL PRNUM16.z
	MVO R4,_screen
	;[238]     print at screenpos(4,11),<3>peek($8000+$1031)
	SRCFILE "pirtoIIDuo.bas",238
	MVII #736,R0
	MVO R0,_screen
	MVI 36913,R0
	MVII #3,R2
	MVI _color,R3
	MVI _screen,R4
	CALL PRNUM16.z
	MVO R4,_screen
	;[239]     print at screenpos(12,11),<3>peek($8000+$1032)
	SRCFILE "pirtoIIDuo.bas",239
	MVII #744,R0
	MVO R0,_screen
	MVI 36914,R0
	MVII #3,R2
	MVI _color,R3
	MVI _screen,R4
	CALL PRNUM16.z
	MVO R4,_screen
	;[240] end if
	SRCFILE "pirtoIIDuo.bas",240
T70:
	;[241] 
	SRCFILE "pirtoIIDuo.bas",241
	;[242]   END
	SRCFILE "pirtoIIDuo.bas",242
	RETURN
	ENDP
	;[243] 
	SRCFILE "pirtoIIDuo.bas",243
	;[244]   ' 32 bitmaps
	SRCFILE "pirtoIIDuo.bas",244
	;[245]     
	SRCFILE "pirtoIIDuo.bas",245
	;[246] debug:  PROCEDURE
	SRCFILE "pirtoIIDuo.bas",246
	; DEBUG
label_DEBUG:	PROC
	BEGIN
	;[247]    cls
	SRCFILE "pirtoIIDuo.bas",247
	CALL CLRSCR
	;[248] looppa:
	SRCFILE "pirtoIIDuo.bas",248
	; LOOPPA
label_LOOPPA:	;[249]  for i=0 to 20:#mem=peek(mfile+i*2):print at screenpos(i,0),(#mem-32)*8+CS_WHITE:next i
	SRCFILE "pirtoIIDuo.bas",249
	CLRR R0
	MVO R0,var_I
T71:
	MVI var_I,R1
	SLL R1,1
	ADDI #33151,R1
	MVI@ R1,R0
	MVO R0,var_&MEM
	MVI var_I,R0
	ADDI #512,R0
	MVO R0,_screen
	MVI var_&MEM,R0
	SUBI #32,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #7,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	MVI var_I,R0
	INCR R0
	MVO R0,var_I
	CMPI #20,R0
	BLE T71
	;[250]  for i=0 to 20:#mem=peek(mfile+i*2+40):print at screenpos(i,1),(#mem-32)*8+CS_WHITE:next i
	SRCFILE "pirtoIIDuo.bas",250
	CLRR R0
	MVO R0,var_I
T72:
	MVI var_I,R1
	SLL R1,1
	ADDI #33191,R1
	MVI@ R1,R0
	MVO R0,var_&MEM
	MVI var_I,R0
	ADDI #532,R0
	MVO R0,_screen
	MVI var_&MEM,R0
	SUBI #32,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #7,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	MVI var_I,R0
	INCR R0
	MVO R0,var_I
	CMPI #20,R0
	BLE T72
	;[251]  for i=0 to 20:#mem=peek(mfile+i*2+80):print at screenpos(i,2),(#mem-32)*8+CS_WHITE:next i
	SRCFILE "pirtoIIDuo.bas",251
	CLRR R0
	MVO R0,var_I
T73:
	MVI var_I,R1
	SLL R1,1
	ADDI #33231,R1
	MVI@ R1,R0
	MVO R0,var_&MEM
	MVI var_I,R0
	ADDI #552,R0
	MVO R0,_screen
	MVI var_&MEM,R0
	SUBI #32,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #7,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	MVI var_I,R0
	INCR R0
	MVO R0,var_I
	CMPI #20,R0
	BLE T73
	;[252]  print at screenpos(0,5),<2>peek(mfile+200)
	SRCFILE "pirtoIIDuo.bas",252
	MVII #612,R0
	MVO R0,_screen
	MVI 33351,R0
	MVII #2,R2
	MVI _color,R3
	MVI _screen,R4
	CALL PRNUM16.z
	MVO R4,_screen
	;[253] print at screenpos(4,5),<6>peek(mfile+202)
	SRCFILE "pirtoIIDuo.bas",253
	MVII #616,R0
	MVO R0,_screen
	MVI 33353,R0
	MVII #6,R2
	MVI _color,R3
	MVI _screen,R4
	CALL PRNUM16.z
	MVO R4,_screen
	;[254] print at screenpos(12,5),<6>peek(mfile+204)
	SRCFILE "pirtoIIDuo.bas",254
	MVII #624,R0
	MVO R0,_screen
	MVI 33355,R0
	MVII #6,R2
	MVI _color,R3
	MVI _screen,R4
	CALL PRNUM16.z
	MVO R4,_screen
	;[255] print at screenpos(0,6),<6>peek(mfile+206)
	SRCFILE "pirtoIIDuo.bas",255
	MVII #632,R0
	MVO R0,_screen
	MVI 33357,R0
	MVII #6,R2
	MVI _color,R3
	MVI _screen,R4
	CALL PRNUM16.z
	MVO R4,_screen
	;[256] print at screenpos(10,6),<6>peek(mfile+212)
	SRCFILE "pirtoIIDuo.bas",256
	MVII #642,R0
	MVO R0,_screen
	MVI 33363,R0
	MVII #6,R2
	MVI _color,R3
	MVI _screen,R4
	CALL PRNUM16.z
	MVO R4,_screen
	;[257] print at screenpos(2,7),<2>peek(mfile+208)
	SRCFILE "pirtoIIDuo.bas",257
	MVII #654,R0
	MVO R0,_screen
	MVI 33359,R0
	MVII #2,R2
	MVI _color,R3
	MVI _screen,R4
	CALL PRNUM16.z
	MVO R4,_screen
	;[258] print at screenpos(5,7),<2>peek(mfile+210)
	SRCFILE "pirtoIIDuo.bas",258
	MVII #657,R0
	MVO R0,_screen
	MVI 33361,R0
	MVII #2,R2
	MVI _color,R3
	MVI _screen,R4
	CALL PRNUM16.z
	MVO R4,_screen
	;[259] 
	SRCFILE "pirtoIIDuo.bas",259
	;[260] if peek(debug)=2 then goto looppa
	SRCFILE "pirtoIIDuo.bas",260
	MVI 33123,R0
	CMPI #2,R0
	BEQ label_LOOPPA
	;[261] end
	SRCFILE "pirtoIIDuo.bas",261
	RETURN
	ENDP
	;[262]  
	SRCFILE "pirtoIIDuo.bas",262
	;[263] 
	SRCFILE "pirtoIIDuo.bas",263
	;[264] reset_sound:    PROCEDURE
	SRCFILE "pirtoIIDuo.bas",264
	; RESET_SOUND
label_RESET_SOUND:	PROC
	BEGIN
	;[265]     SOUND 0,1,0
	SRCFILE "pirtoIIDuo.bas",265
	MVII #1,R0
	MVO R0,496
	SWAP R0
	MVO R0,500
	CLRR R0
	MVO R0,507
	;[266]     SOUND 1,1,0
	SRCFILE "pirtoIIDuo.bas",266
	MVII #1,R0
	MVO R0,497
	SWAP R0
	MVO R0,501
	CLRR R0
	MVO R0,508
	;[267]     SOUND 2,1,0
	SRCFILE "pirtoIIDuo.bas",267
	MVII #1,R0
	MVO R0,498
	SWAP R0
	MVO R0,502
	CLRR R0
	MVO R0,509
	;[268]     SOUND 4,,$38
	SRCFILE "pirtoIIDuo.bas",268
	MVII #56,R0
	MVO R0,504
	;[269]     RETURN
	SRCFILE "pirtoIIDuo.bas",269
	RETURN
	;[270]     END
	SRCFILE "pirtoIIDuo.bas",270
	ENDP
	;[271] 
	SRCFILE "pirtoIIDuo.bas",271
	;[272] 
	SRCFILE "pirtoIIDuo.bas",272
	;[273] screen_bitmaps_0:
	SRCFILE "pirtoIIDuo.bas",273
	; SCREEN_BITMAPS_0
label_SCREEN_BITMAPS_0:	;[274]     DATA $0000,$0000,$3F00,$FF7F
	SRCFILE "pirtoIIDuo.bas",274
	DECLE 0
	DECLE 0
	DECLE 16128
	DECLE 65407
	;[275]     DATA $0000,$0000,$FF00,$FFFF
	SRCFILE "pirtoIIDuo.bas",275
	DECLE 0
	DECLE 0
	DECLE 65280
	DECLE 65535
	;[276]     DATA $0000,$0000,$0301,$0303
	SRCFILE "pirtoIIDuo.bas",276
	DECLE 0
	DECLE 0
	DECLE 769
	DECLE 771
	;[277]     DATA $0000,$0000,$FFFF,$F1FF
	SRCFILE "pirtoIIDuo.bas",277
	DECLE 0
	DECLE 0
	DECLE 65535
	DECLE 61951
	;[278]     DATA $0000,$0000,$F180,$FCF9
	SRCFILE "pirtoIIDuo.bas",278
	DECLE 0
	DECLE 0
	DECLE 61824
	DECLE 64761
	;[279]     DATA $0000,$0000,$FFFF,$1FFF
	SRCFILE "pirtoIIDuo.bas",279
	DECLE 0
	DECLE 0
	DECLE 65535
	DECLE 8191
	;[280]     DATA $0000,$0000,$FCFE,$80FC
	SRCFILE "pirtoIIDuo.bas",280
	DECLE 0
	DECLE 0
	DECLE 64766
	DECLE 33020
	;[281]     DATA $0000,$0000,$1F03,$F87F
	SRCFILE "pirtoIIDuo.bas",281
	DECLE 0
	DECLE 0
	DECLE 7939
	DECLE 63615
	;[282]     DATA $0000,$0000,$F0C0,$FCF8
	SRCFILE "pirtoIIDuo.bas",282
	DECLE 0
	DECLE 0
	DECLE 61632
	DECLE 64760
	;[283]     DATA $8CCC,$0C0C,$1C0C,$3C1C
	SRCFILE "pirtoIIDuo.bas",283
	DECLE 36044
	DECLE 3084
	DECLE 7180
	DECLE 15388
	;[284]     DATA $7070,$7070,$7070,$7170
	SRCFILE "pirtoIIDuo.bas",284
	DECLE 28784
	DECLE 28784
	DECLE 28784
	DECLE 29040
	;[285]     DATA $0703,$0707,$0F0F,$0F0F
	SRCFILE "pirtoIIDuo.bas",285
	DECLE 1795
	DECLE 1799
	DECLE 3855
	DECLE 3855
	;[286]     DATA $E1E0,$FFE3,$FFFF,$FFFF
	SRCFILE "pirtoIIDuo.bas",286
	DECLE 57824
	DECLE 65507
	DECLE 65535
	DECLE 65535
	;[287]     DATA $F8FC,$F0F8,$00E0,$8000
	SRCFILE "pirtoIIDuo.bas",287
	DECLE 63740
	DECLE 61688
	DECLE 224
	DECLE 32768
	;[288]     DATA $1F1F,$3F1F,$3E3F,$7E3E
	SRCFILE "pirtoIIDuo.bas",288
	DECLE 7967
	DECLE 16159
	DECLE 15935
	DECLE 32318
	;[289]     DATA $0381,$0703,$0707,$0707
	SRCFILE "pirtoIIDuo.bas",289
	DECLE 897
	DECLE 1795
	DECLE 1799
	DECLE 1799
	;[290] screen_bitmaps_1:
	SRCFILE "pirtoIIDuo.bas",290
	; SCREEN_BITMAPS_1
label_SCREEN_BITMAPS_1:	;[291]     DATA $F0F0,$E0F0,$E0E0,$C1C0
	SRCFILE "pirtoIIDuo.bas",291
	DECLE 61680
	DECLE 57584
	DECLE 57568
	DECLE 49600
	;[292]     DATA $7C7C,$FC7C,$FCFC,$F8F8
	SRCFILE "pirtoIIDuo.bas",292
	DECLE 31868
	DECLE 64636
	DECLE 64764
	DECLE 63736
	;[293]     DATA $7838,$3078,$0000,$0000
	SRCFILE "pirtoIIDuo.bas",293
	DECLE 30776
	DECLE 12408
	DECLE 0
	DECLE 0
	;[294]     DATA $7673,$1C3E,$0000,$0000
	SRCFILE "pirtoIIDuo.bas",294
	DECLE 30323
	DECLE 7230
	DECLE 0
	DECLE 0
	;[295]     DATA $1F1F,$3F1F,$003F,$0000
	SRCFILE "pirtoIIDuo.bas",295
	DECLE 7967
	DECLE 16159
	DECLE 63
	DECLE 0
	;[296]     DATA $9F9F,$8F8F,$0007,$0000
	SRCFILE "pirtoIIDuo.bas",296
	DECLE 40863
	DECLE 36751
	DECLE 7
	DECLE 0
	;[297]     DATA $C080,$E0E0,$00F0,$0000
	SRCFILE "pirtoIIDuo.bas",297
	DECLE 49280
	DECLE 57568
	DECLE 240
	DECLE 0
	;[298]     DATA $7C7C,$FC7C,$00F8,$0000
	SRCFILE "pirtoIIDuo.bas",298
	DECLE 31868
	DECLE 64636
	DECLE 248
	DECLE 0
	;[299]     DATA $0707,$0103,$0000,$0000
	SRCFILE "pirtoIIDuo.bas",299
	DECLE 1799
	DECLE 259
	DECLE 0
	DECLE 0
	;[300]     DATA $E3C1,$FFFF,$0078,$0000
	SRCFILE "pirtoIIDuo.bas",300
	DECLE 58305
	DECLE 65535
	DECLE 120
	DECLE 0
	;[301]     DATA $E0F0,$00C0,$0000,$0000
	SRCFILE "pirtoIIDuo.bas",301
	DECLE 57584
	DECLE 192
	DECLE 0
	DECLE 0
	;[302] 
	SRCFILE "pirtoIIDuo.bas",302
	;[303]     ' Real Copyright Symbol
	SRCFILE "pirtoIIDuo.bas",303
	;[304]     BITMAP ".######."
	SRCFILE "pirtoIIDuo.bas",304
	;[305]     BITMAP "#......#"
	SRCFILE "pirtoIIDuo.bas",305
	DECLE 33150
	;[306]     BITMAP "#..###.#"
	SRCFILE "pirtoIIDuo.bas",306
	;[307]     BITMAP "#.#....#"
	SRCFILE "pirtoIIDuo.bas",307
	DECLE 41373
	;[308]     BITMAP "#.#....#"
	SRCFILE "pirtoIIDuo.bas",308
	;[309]     BITMAP "#..###.#"
	SRCFILE "pirtoIIDuo.bas",309
	DECLE 40353
	;[310]     BITMAP "#......#"
	SRCFILE "pirtoIIDuo.bas",310
	;[311]     BITMAP ".######."
	SRCFILE "pirtoIIDuo.bas",311
	DECLE 32385
	;[312] 
	SRCFILE "pirtoIIDuo.bas",312
	;[313] BITMAP "....##.."
	SRCFILE "pirtoIIDuo.bas",313
	;[314] BITMAP "......#."
	SRCFILE "pirtoIIDuo.bas",314
	DECLE 524
	;[315] BITMAP ".......#"
	SRCFILE "pirtoIIDuo.bas",315
	;[316] BITMAP ".......#"
	SRCFILE "pirtoIIDuo.bas",316
	DECLE 257
	;[317] BITMAP "........"
	SRCFILE "pirtoIIDuo.bas",317
	;[318] BITMAP "........"
	SRCFILE "pirtoIIDuo.bas",318
	DECLE 0
	;[319] BITMAP "........"
	SRCFILE "pirtoIIDuo.bas",319
	;[320] BITMAP "........"
	SRCFILE "pirtoIIDuo.bas",320
	DECLE 0
	;[321] 
	SRCFILE "pirtoIIDuo.bas",321
	;[322] BITMAP "........"
	SRCFILE "pirtoIIDuo.bas",322
	;[323] BITMAP "........"
	SRCFILE "pirtoIIDuo.bas",323
	DECLE 0
	;[324] BITMAP "........"
	SRCFILE "pirtoIIDuo.bas",324
	;[325] BITMAP "........"
	SRCFILE "pirtoIIDuo.bas",325
	DECLE 0
	;[326] BITMAP ".......#"
	SRCFILE "pirtoIIDuo.bas",326
	;[327] BITMAP ".......#"
	SRCFILE "pirtoIIDuo.bas",327
	DECLE 257
	;[328] BITMAP "......#."
	SRCFILE "pirtoIIDuo.bas",328
	;[329] BITMAP "....##.."
	SRCFILE "pirtoIIDuo.bas",329
	DECLE 3074
	;[330] 
	SRCFILE "pirtoIIDuo.bas",330
	;[331] BITMAP "........"
	SRCFILE "pirtoIIDuo.bas",331
	;[332] BITMAP "........"
	SRCFILE "pirtoIIDuo.bas",332
	DECLE 0
	;[333] BITMAP "........"
	SRCFILE "pirtoIIDuo.bas",333
	;[334] BITMAP "........"
	SRCFILE "pirtoIIDuo.bas",334
	DECLE 0
	;[335] BITMAP "#......."
	SRCFILE "pirtoIIDuo.bas",335
	;[336] BITMAP "#......."
	SRCFILE "pirtoIIDuo.bas",336
	DECLE 32896
	;[337] BITMAP ".#......"
	SRCFILE "pirtoIIDuo.bas",337
	;[338] BITMAP "..##...."
	SRCFILE "pirtoIIDuo.bas",338
	DECLE 12352
	;[339] 
	SRCFILE "pirtoIIDuo.bas",339
	;[340] BITMAP "..##...."
	SRCFILE "pirtoIIDuo.bas",340
	;[341] BITMAP ".#......"
	SRCFILE "pirtoIIDuo.bas",341
	DECLE 16432
	;[342] BITMAP "#......."
	SRCFILE "pirtoIIDuo.bas",342
	;[343] BITMAP "#......."
	SRCFILE "pirtoIIDuo.bas",343
	DECLE 32896
	;[344] BITMAP "........"
	SRCFILE "pirtoIIDuo.bas",344
	;[345] BITMAP "........"
	SRCFILE "pirtoIIDuo.bas",345
	DECLE 0
	;[346] BITMAP "........"
	SRCFILE "pirtoIIDuo.bas",346
	;[347] BITMAP "........"
	SRCFILE "pirtoIIDuo.bas",347
	DECLE 0
	;[348] 
	SRCFILE "pirtoIIDuo.bas",348
	;[349] 
	SRCFILE "pirtoIIDuo.bas",349
	;[350]     REM 20x12 cards
	SRCFILE "pirtoIIDuo.bas",350
	;[351] screen_cards:
	SRCFILE "pirtoIIDuo.bas",351
	; SCREEN_CARDS
label_SCREEN_CARDS:	;[352]     DATA $0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	SRCFILE "pirtoIIDuo.bas",352
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	;[353]     DATA $0000,$0000,$0000,$0000,$0000,$0802,$080A,$0000,$0812,$081A,$0822,$082A,$0832,$083A,$0842,$0000,$0000,$0000,$0000,$0000
	SRCFILE "pirtoIIDuo.bas",353
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 2050
	DECLE 2058
	DECLE 0
	DECLE 2066
	DECLE 2074
	DECLE 2082
	DECLE 2090
	DECLE 2098
	DECLE 2106
	DECLE 2114
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	;[354]     DATA $0000,$0000,$0000,$0000,$0000,$084A,$0852,$0000,$085A,$0862,$086A,$0872,$087A,$0882,$088A,$0000,$0000,$0000,$0000,$0000
	SRCFILE "pirtoIIDuo.bas",354
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 2122
	DECLE 2130
	DECLE 0
	DECLE 2138
	DECLE 2146
	DECLE 2154
	DECLE 2162
	DECLE 2170
	DECLE 2178
	DECLE 2186
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	;[355]     DATA $0000,$0000,$0000,$0000,$0000,$0892,$089A,$0000,$08A2,$08AA,$08B2,$08BA,$08C2,$08CA,$08D2,$0000,$0000,$0000,$0000,$0000
	SRCFILE "pirtoIIDuo.bas",355
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 2194
	DECLE 2202
	DECLE 0
	DECLE 2210
	DECLE 2218
	DECLE 2226
	DECLE 2234
	DECLE 2242
	DECLE 2250
	DECLE 2258
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	;[356]     DATA $0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	SRCFILE "pirtoIIDuo.bas",356
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	;[357]     DATA $0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	SRCFILE "pirtoIIDuo.bas",357
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	;[358]     DATA $0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	SRCFILE "pirtoIIDuo.bas",358
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	;[359]     DATA $0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	SRCFILE "pirtoIIDuo.bas",359
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	;[360]     DATA $0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	SRCFILE "pirtoIIDuo.bas",360
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	;[361]     DATA $0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	SRCFILE "pirtoIIDuo.bas",361
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	;[362]     DATA $0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	SRCFILE "pirtoIIDuo.bas",362
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	;[363]     DATA $0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000,$0000
	SRCFILE "pirtoIIDuo.bas",363
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	DECLE 0
	;ENDFILE
	;ENDFILE
	SRCFILE "",0
	;
	; Epilogue for IntyBASIC programs
	; by Oscar Toledo G.  http://nanochess.org/
	;
	; Revision: Jan/30/2014. Moved GRAM code below MOB updates.
	;                        Added comments.
	; Revision: Feb/26/2014. Optimized access to collision registers
	;                        per DZ-Jay suggestion. Added scrolling
	;                        routines with optimization per intvnut
	;                        suggestion. Added border/mask support.
	; Revision: Apr/02/2014. Added support to set MODE (color stack
	;                        or foreground/background), added support
	;                        for SCREEN statement.
	; Revision: Aug/19/2014. Solved bug in bottom scroll, moved an
	;                        extra unneeded line.
	; Revision: Aug/26/2014. Integrated music player and NTSC/PAL
	;                        detection.
	; Revision: Oct/24/2014. Adjust in some comments.
	; Revision: Nov/13/2014. Integrated Joseph Zbiciak's routines
	;                        for printing numbers.
	; Revision: Nov/17/2014. Redesigned MODE support to use a single
	;                        variable.
	; Revision: Nov/21/2014. Added Intellivoice support routines made
	;                        by Joseph Zbiciak.
	; Revision: Dec/11/2014. Optimized keypad decode routines.
	; Revision: Jan/25/2015. Added marker for insertion of ON FRAME GOSUB
	; Revision: Feb/17/2015. Allows to deactivate music player (PLAY NONE)
	; Revision: Apr/21/2015. Accelerates common case of keypad not pressed.
	;                        Added ECS ROM disable code.
	; Revision: Apr/22/2015. Added Joseph Zbiciak accelerated multiplication
	;                        routines.
	; Revision: Jun/04/2015. Optimized play_music (per GroovyBee suggestion)
	; Revision: Jul/25/2015. Added infinite loop at start to avoid crashing
	;                        with empty programs. Solved bug where _color
	;                        didn't started with white.
	; Revision: Aug/20/2015. Moved ECS mapper disable code so nothing gets
	;                        after it (GroovyBee 42K sample code)
	; Revision: Aug/21/2015. Added Joseph Zbiciak routines for JLP Flash
	;                        handling.
	; Revision: Aug/31/2015. Added CPYBLK2 for SCREEN fifth argument.
	; Revision: Sep/01/2015. Defined labels Q1 and Q2 as alias.
	; Revision: Jan/22/2016. Music player allows not to use noise channel
	;                        for drums. Allows setting music volume.
	; Revision: Jan/23/2016. Added jump inside of music (for MUSIC JUMP)
	; Revision: May/03/2016. Preserves current mode in bit 0 of _mode_select
	; Revision: Oct/21/2016. Added C7 in notes table, it was missing. (thanks
	;                        mmarrero)
	; Revision: Jan/09/2018. Initializes scroll offset registers (useful when
	;                        starting from $4800). Uses slightly less space.
	; Revision: Feb/05/2018. Added IV_HUSH.
	; Revision: Mar/01/2018. Added support for music tracker over ECS.
	; Revision: Sep/25/2018. Solved bug in mixer for ECS drums.
	; Revision: Oct/30/2018. Small optimization in music player.
	; Revision: Jan/09/2019. Solved bug where it would play always like
	;                        PLAY SIMPLE NO DRUMS.
	; Revision: May/18/2019. Solved bug where drums failed in ECS side.
	;

	;
	; Avoids empty programs to crash
	; 
stuck:	B stuck

	ROM.SelectDefaultSegment

	;
	; Copy screen helper for SCREEN wide statement
	;

CPYBLK2:	PROC
	MOVR R0,R3		; Offset
	MOVR R5,R2
	PULR R0
	PULR R1
	PULR R5
	PULR R4
	PSHR R2
	SUBR R1,R3

@@1:	PSHR R3
	MOVR R1,R3		; Init line copy
@@2:	MVI@ R4,R2		; Copy line
	MVO@ R2,R5
	DECR R3
	BNE @@2
	PULR R3		 ; Add offset to start in next line
	ADDR R3,R4
	SUBR R1,R5
	ADDI #20,R5
	DECR R0		 ; Count lines
	BNE @@1

	RETURN
	ENDP

	;
	; Copy screen helper for SCREEN statement
	;
CPYBLK:	PROC
	BEGIN
	MOVR R3,R4
	MOVR R2,R5

@@1:	MOVR R1,R3	      ; Init line copy
@@2:	MVI@ R4,R2	      ; Copy line
	MVO@ R2,R5
	DECR R3
	BNE @@2
	MVII #20,R3	     ; Add offset to start in next line
	SUBR R1,R3
	ADDR R3,R4
	ADDR R3,R5
	DECR R0		 ; Count lines
	BNE @@1
	RETURN
	ENDP

	;
	; Wait for interruption
	;
_wait:  PROC

    IF intybasic_keypad
	MVI $01FF,R0
	COMR R0
	ANDI #$FF,R0
	CMP _cnt1_p0,R0
	BNE @@2
	CMP _cnt1_p1,R0
	BNE @@2
	TSTR R0		; Accelerates common case of key not pressed
	MVII #_keypad_table+13,R4
	BEQ @@4
	MVII #_keypad_table,R4
    REPEAT 6
	CMP@ R4,R0
	BEQ @@4
	CMP@ R4,R0
	BEQ @@4
    ENDR
	INCR R4
@@4:    SUBI #_keypad_table+1,R4
	MVO R4,_cnt1_key

@@2:    MVI _cnt1_p1,R1
	MVO R1,_cnt1_p0
	MVO R0,_cnt1_p1

	MVI $01FE,R0
	COMR R0
	ANDI #$FF,R0
	CMP _cnt2_p0,R0
	BNE @@5
	CMP _cnt2_p1,R0
	BNE @@5
	TSTR R0		; Accelerates common case of key not pressed
	MVII #_keypad_table+13,R4
	BEQ @@7
	MVII #_keypad_table,R4
    REPEAT 6
	CMP@ R4,R0
	BEQ @@7
	CMP@ R4,R0
	BEQ @@7
    ENDR

	INCR R4
@@7:    SUBI #_keypad_table+1,R4
	MVO R4,_cnt2_key

@@5:    MVI _cnt2_p1,R1
	MVO R1,_cnt2_p0
	MVO R0,_cnt2_p1
    ENDI

	CLRR    R0
	MVO     R0,_int	 ; Clears waiting flag
@@1:	CMP     _int,  R0       ; Waits for change
	BEQ     @@1
	JR      R5	      ; Returns
	ENDP

	;
	; Keypad table
	;
_keypad_table:	  PROC
	DECLE $48,$81,$41,$21,$82,$42,$22,$84,$44,$24,$88,$28
	ENDP

_set_isr:	PROC
	MVI@ R5,R0
	MVO R0,ISRVEC
	SWAP R0
	MVO R0,ISRVEC+1
	JR R5
	ENDP

	;
	; Interruption routine
	;
_int_vector:     PROC

    IF intybasic_stack
	CMPI #$308,R6
	BNC @@vs
	MVO R0,$20	; Enables display
	MVI $21,R0	; Activates Color Stack mode
	CLRR R0
	MVO R0,$28
	MVO R0,$29
	MVO R0,$2A
	MVO R0,$2B
	MVII #@@vs1,R4
	MVII #$200,R5
	MVII #20,R1
@@vs2:	MVI@ R4,R0
	MVO@ R0,R5
	DECR R1
	BNE @@vs2
	RETURN

	; Stack Overflow message
@@vs1:	DECLE 0,0,0,$33*8+7,$54*8+7,$41*8+7,$43*8+7,$4B*8+7,$00*8+7
	DECLE $4F*8+7,$56*8+7,$45*8+7,$52*8+7,$46*8+7,$4C*8+7
	DECLE $4F*8+7,$57*8+7,0,0,0

@@vs:
    ENDI

	MVII #1,R1
	MVO R1,_int	; Indicates interrupt happened.

	MVI _mode_select,R0
	SARC R0,2
	BNE @@ds
	MVO R0,$20	; Enables display
@@ds:	BNC @@vi14
	MVO R0,$21	; Foreground/background mode
	BNOV @@vi0
	B @@vi15

@@vi14:	MVI $21,R0	; Color stack mode
	BNOV @@vi0
	CLRR R1
	MVI _color,R0
	MVO R0,$28
	SWAP R0
	MVO R0,$29
	SLR R0,2
	SLR R0,2
	MVO R0,$2A
	SWAP R0
	MVO R0,$2B
@@vi15:
	MVO R1,_mode_select
	MVII #7,R0
	MVO R0,_color	   ; Default color for PRINT "string"
@@vi0:

	BEGIN

	MVI _border_color,R0
	MVO     R0,     $2C     ; Border color
	MVI _border_mask,R0
	MVO     R0,     $32     ; Border mask
    IF intybasic_col
	;
	; Save collision registers for further use and clear them
	;
	MVII #$18,R4
	MVII #_col0,R5
	MVI@ R4,R0
	MVO@ R0,R5  ; _col0
	MVI@ R4,R0
	MVO@ R0,R5  ; _col1
	MVI@ R4,R0
	MVO@ R0,R5  ; _col2
	MVI@ R4,R0
	MVO@ R0,R5  ; _col3
	MVI@ R4,R0
	MVO@ R0,R5  ; _col4
	MVI@ R4,R0
	MVO@ R0,R5  ; _col5
	MVI@ R4,R0
	MVO@ R0,R5  ; _col6
	MVI@ R4,R0
	MVO@ R0,R5  ; _col7
    ENDI
	
    IF intybasic_scroll

	;
	; Scrolling things
	;
	MVI _scroll_x,R0
	MVO R0,$30
	MVI _scroll_y,R0
	MVO R0,$31
    ENDI

	;
	; Updates sprites (MOBs)
	;
	MVII #_mobs,R4
	CLRR R5		; X-coordinates
    REPEAT 8
	MVI@ R4,R0
	MVO@ R0,R5
	MVI@ R4,R0
	MVO@ R0,R5
	MVI@ R4,R0
	MVO@ R0,R5
    ENDR
    IF intybasic_col
	CLRR R0		; Erase collision bits (R5 = $18)
	MVO@ R0,R5
	MVO@ R0,R5
	MVO@ R0,R5
	MVO@ R0,R5
	MVO@ R0,R5
	MVO@ R0,R5
	MVO@ R0,R5
	MVO@ R0,R5
    ENDI

    IF intybasic_music
     	MVI _ntsc,R0
	RRC R0,1	 ; PAL?
	BNC @@vo97      ; Yes, always emit sound
	MVI _music_frame,R0
	INCR R0
	CMPI #6,R0
	BNE @@vo14
	CLRR R0
@@vo14:	MVO R0,_music_frame
	BEQ @@vo15
@@vo97:	CALL _emit_sound
    IF intybasic_music_ecs
	CALL _emit_sound_ecs
    ENDI
@@vo15:
    ENDI

	;
	; Detect GRAM definition
	;
	MVI _gram_bitmap,R4
	TSTR R4
	BEQ @@vi1
	MVI _gram_target,R1
	SLL R1,2
	SLL R1,1
	ADDI #$3800,R1
	MOVR R1,R5
	MVI _gram_total,R0
@@vi3:
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	DECR R0
	BNE @@vi3
	MVO R0,_gram_bitmap
@@vi1:
	MVI _gram2_bitmap,R4
	TSTR R4
	BEQ @@vii1
	MVI _gram2_target,R1
	SLL R1,2
	SLL R1,1
	ADDI #$3800,R1
	MOVR R1,R5
	MVI _gram2_total,R0
@@vii3:
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	MVI@    R4,     R1
	MVO@    R1,     R5
	SWAP    R1
	MVO@    R1,     R5
	DECR R0
	BNE @@vii3
	MVO R0,_gram2_bitmap
@@vii1:

    IF intybasic_scroll
	;
	; Frame scroll support
	;
	MVI _scroll_d,R0
	TSTR R0
	BEQ @@vi4
	CLRR R1
	MVO R1,_scroll_d
	DECR R0     ; Left
	BEQ @@vi5
	DECR R0     ; Right
	BEQ @@vi6
	DECR R0     ; Top
	BEQ @@vi7
	DECR R0     ; Bottom
	BEQ @@vi8
	B @@vi4

@@vi5:  MVII #$0200,R4
	MOVR R4,R5
	INCR R5
	MVII #12,R1
@@vi12: MVI@ R4,R2
	MVI@ R4,R3
	REPEAT 8
	MVO@ R2,R5
	MVI@ R4,R2
	MVO@ R3,R5
	MVI@ R4,R3
	ENDR
	MVO@ R2,R5
	MVI@ R4,R2
	MVO@ R3,R5
	MVO@ R2,R5
	INCR R4
	INCR R5
	DECR R1
	BNE @@vi12
	B @@vi4

@@vi6:  MVII #$0201,R4
	MVII #$0200,R5
	MVII #12,R1
@@vi11:
	REPEAT 19
	MVI@ R4,R0
	MVO@ R0,R5
	ENDR
	INCR R4
	INCR R5
	DECR R1
	BNE @@vi11
	B @@vi4
    
	;
	; Complex routine to be ahead of STIC display
	; Moves first the top 6 lines, saves intermediate line
	; Then moves the bottom 6 lines and restores intermediate line
	;
@@vi7:  MVII #$0264,R4
	MVII #5,R1
	MVII #_scroll_buffer,R5
	REPEAT 20
	MVI@ R4,R0
	MVO@ R0,R5
	ENDR
	SUBI #40,R4
	MOVR R4,R5
	ADDI #20,R5
@@vi10:
	REPEAT 20
	MVI@ R4,R0
	MVO@ R0,R5
	ENDR
	SUBI #40,R4
	SUBI #40,R5
	DECR R1
	BNE @@vi10
	MVII #$02C8,R4
	MVII #$02DC,R5
	MVII #5,R1
@@vi13:
	REPEAT 20
	MVI@ R4,R0
	MVO@ R0,R5
	ENDR
	SUBI #40,R4
	SUBI #40,R5
	DECR R1
	BNE @@vi13
	MVII #_scroll_buffer,R4
	REPEAT 20
	MVI@ R4,R0
	MVO@ R0,R5
	ENDR
	B @@vi4

@@vi8:  MVII #$0214,R4
	MVII #$0200,R5
	MVII #$DC/4,R1
@@vi9:  
	REPEAT 4
	MVI@ R4,R0
	MVO@ R0,R5
	ENDR
	DECR R1
	BNE @@vi9
	B @@vi4

@@vi4:
    ENDI

    IF intybasic_voice
	;
	; Intellivoice support
	;
	CALL IV_ISR
    ENDI

	;
	; Random number generator
	;
	CALL _next_random

    IF intybasic_music
	; Generate sound for next frame
       	MVI _ntsc,R0
	RRC R0,1	 ; PAL?
	BNC @@vo98      ; Yes, always generate sound
	MVI _music_frame,R0
	TSTR R0
	BEQ @@vo16
@@vo98: CALL _generate_music
@@vo16:
    ENDI

	; Increase frame number
	MVI _frame,R0
	INCR R0
	MVO R0,_frame

	; This mark is for ON FRAME GOSUB support

	RETURN
	ENDP

	;
	; Generates the next random number
	;
_next_random:	PROC

MACRO _ROR
	RRC R0,1
	MOVR R0,R2
	SLR R2,2
	SLR R2,2
	ANDI #$0800,R2
	SLR R2,2
	SLR R2,2
	ANDI #$007F,R0
	XORR R2,R0
ENDM
	MVI _rand,R0
	SETC
	_ROR
	XOR _frame,R0
	_ROR
	XOR _rand,R0
	_ROR
	XORI #9,R0
	MVO R0,_rand
	JR R5
	ENDP

    IF intybasic_music

	;
	; Music player, comes from my game Princess Quest for Intellivision
	; so it's a practical tracker used in a real game ;) and with enough
	; features.
	;

	; NTSC frequency for notes (based on 3.579545 mhz)
ntsc_note_table:    PROC
	; Silence - 0
	DECLE 0
	; Octave 2 - 1
	DECLE 1721,1621,1532,1434,1364,1286,1216,1141,1076,1017,956,909
	; Octave 3 - 13
	DECLE 854,805,761,717,678,639,605,571,538,508,480,453
	; Octave 4 - 25
	DECLE 427,404,380,360,339,321,302,285,270,254,240,226
	; Octave 5 - 37
	DECLE 214,202,191,180,170,160,151,143,135,127,120,113
	; Octave 6 - 49
	DECLE 107,101,95,90,85,80,76,71,67,64,60,57
	; Octave 7 - 61
	DECLE 54
	; Space for two notes more
	ENDP

	; PAL frequency for notes (based on 4 mhz)
pal_note_table:    PROC
	; Silence - 0
	DECLE 0
	; Octava 2 - 1
	DECLE 1923,1812,1712,1603,1524,1437,1359,1276,1202,1136,1068,1016
	; Octava 3 - 13
	DECLE 954,899,850,801,758,714,676,638,601,568,536,506
	; Octava 4 - 25
	DECLE 477,451,425,402,379,358,338,319,301,284,268,253
	; Octava 5 - 37
	DECLE 239,226,213,201,190,179,169,159,150,142,134,127
	; Octava 6 - 49
	DECLE 120,113,106,100,95,89,84,80,75,71,67,63
	; Octava 7 - 61
	DECLE 60
	; Space for two notes more
	ENDP
    ENDI

	;
	; Music tracker init
	;
_init_music:	PROC
    IF intybasic_music
	MVI _ntsc,R0
	RRC R0,1
	MVII #ntsc_note_table,R0
	BC @@0
	MVII #pal_note_table,R0
@@0:	MVO R0,_music_table
	MVII #$38,R0	; $B8 blocks controllers o.O!
	MVO R0,_music_mix
    IF intybasic_music_ecs
	MVO R0,_music2_mix
    ENDI
	CLRR R0
    ELSE
	JR R5		; Tracker disabled (no PLAY statement used)
    ENDI
	ENDP

    IF intybasic_music
	;
	; Start music
	; R0 = Pointer to music
	;
_play_music:	PROC
	MVII #1,R1
	MOVR R1,R3
	MOVR R0,R2
	BEQ @@1
	MVI@ R2,R3
	INCR R2
@@1:	MVO R2,_music_p
	MVO R2,_music_start
	SWAP R2
	MVO R2,_music_start+1
	MVO R3,_music_t
	MVO R1,_music_tc
	JR R5

	ENDP

	;
	; Generate music
	;
_generate_music:	PROC
	BEGIN
	MVI _music_mix,R0
	ANDI #$C0,R0
	XORI #$38,R0
	MVO R0,_music_mix
    IF intybasic_music_ecs
	MVI _music2_mix,R0
	ANDI #$C0,R0
	XORI #$38,R0
	MVO R0,_music2_mix
    ENDI
	CLRR R1			; Turn off volume for the three sound channels
	MVO R1,_music_vol1
	MVO R1,_music_vol2
	MVI _music_tc,R3
	MVO R1,_music_vol3
    IF intybasic_music_ecs
	MVO R1,_music2_vol1
	NOP
	MVO R1,_music2_vol2
	MVO R1,_music2_vol3
    ENDI
	DECR R3
	MVO R3,_music_tc
	BNE @@6
	; R3 is zero from here up to @@6
	MVI _music_p,R4
@@15:	TSTR R4		; Silence?
	BEQ @@43	; Keep quiet
@@41:	MVI@ R4,R0
	MVI@ R4,R1
	MVI _music_t,R2
	CMPI #$FA00,R1	; Volume?
	BNC @@42
    IF intybasic_music_volume
	BEQ @@40
    ENDI
	CMPI #$FF00,R1	; Speed?
	BEQ @@39
	CMPI #$FB00,R1	; Return?
	BEQ @@38
	CMPI #$FC00,R1	; Gosub?
	BEQ @@37
	CMPI #$FE00,R1	; The end?
	BEQ @@36       ; Keep quiet
;	CMPI #$FD00,R1	; Repeat?
;	BNE @@42
	MVI _music_start+1,R0
	SWAP R0
	ADD _music_start,R0
	MOVR R0,R4
	B @@15

    IF intybasic_music_volume
@@40:	
	MVO R0,_music_vol
	B @@41
    ENDI

@@39:	MVO R0,_music_t
	MOVR R0,R2
	B @@41

@@38:	MVI _music_gosub,R4
	B @@15

@@37:	MVO R4,_music_gosub
@@36:	MOVR R0,R4	; Jump, zero will make it quiet
	B @@15

@@43:	MVII #1,R0
	MVO R0,_music_tc
	B @@0
	
@@42: 	MVO R2,_music_tc    ; Restart note time
     	MVO R4,_music_p
     	
	MOVR R0,R2
	ANDI #$FF,R2
	CMPI #$3F,R2	; Sustain note?
	BEQ @@1
	MOVR R2,R4
	ANDI #$3F,R4
	MVO R4,_music_n1	; Note
	MVO R3,_music_s1	; Waveform
	ANDI #$C0,R2
	MVO R2,_music_i1	; Instrument
	
@@1:	SWAP R0
	ANDI #$FF,R0
	CMPI #$3F,R0	; Sustain note?
	BEQ @@2
	MOVR R0,R4
	ANDI #$3F,R4
	MVO R4,_music_n2	; Note
	MVO R3,_music_s2	; Waveform
	ANDI #$C0,R0
	MVO R0,_music_i2	; Instrument
	
@@2:	MOVR R1,R2
	ANDI #$FF,R2
	CMPI #$3F,R2	; Sustain note?
	BEQ @@3
	MOVR R2,R4
	ANDI #$3F,R4
	MVO R4,_music_n3	; Note
	MVO R3,_music_s3	; Waveform
	ANDI #$C0,R2
	MVO R2,_music_i3	; Instrument
	
@@3:	SWAP R1
	MVO R1,_music_n4
	MVO R3,_music_s4
	
    IF intybasic_music_ecs
	MVI _music_p,R4
	MVI@ R4,R0
	MVI@ R4,R1
	MVO R4,_music_p

	MOVR R0,R2
	ANDI #$FF,R2
	CMPI #$3F,R2	; Sustain note?
	BEQ @@33
	MOVR R2,R4
	ANDI #$3F,R4
	MVO R4,_music_n5	; Note
	MVO R3,_music_s5	; Waveform
	ANDI #$C0,R2
	MVO R2,_music_i5	; Instrument
	
@@33:	SWAP R0
	ANDI #$FF,R0
	CMPI #$3F,R0	; Sustain note?
	BEQ @@34
	MOVR R0,R4
	ANDI #$3F,R4
	MVO R4,_music_n6	; Note
	MVO R3,_music_s6	; Waveform
	ANDI #$C0,R0
	MVO R0,_music_i6	; Instrument
	
@@34:	MOVR R1,R2
	ANDI #$FF,R2
	CMPI #$3F,R2	; Sustain note?
	BEQ @@35
	MOVR R2,R4
	ANDI #$3F,R4
	MVO R4,_music_n7	; Note
	MVO R3,_music_s7	; Waveform
	ANDI #$C0,R2
	MVO R2,_music_i7	; Instrument
	
@@35:	MOVR R1,R2
	SWAP R2
	MVO R2,_music_n8
	MVO R3,_music_s8
	
    ENDI

	;
	; Construct main voice
	;
@@6:	MVI _music_n1,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@7		; No, jump
	MVI _music_s1,R1
	MVI _music_i1,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music_freq10	; Note in voice A
	SWAP R3
	MVO R3,_music_freq11
	MVO R1,_music_vol1
	; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@20
	SUBI #$08,R0
@@20:	MVO R0,_music_s1

@@7:	MVI _music_n2,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@8		; No, jump
	MVI _music_s2,R1
	MVI _music_i2,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music_freq20	; Note in voice B
	SWAP R3
	MVO R3,_music_freq21
	MVO R1,_music_vol2
	; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@21
	SUBI #$08,R0
@@21:	MVO R0,_music_s2

@@8:	MVI _music_n3,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@9		; No, jump
	MVI _music_s3,R1
	MVI _music_i3,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music_freq30	; Note in voice C
	SWAP R3
	MVO R3,_music_freq31
	MVO R1,_music_vol3
	; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@22
	SUBI #$08,R0
@@22:	MVO R0,_music_s3

@@9:	MVI _music_n4,R0	; Read drum
	DECR R0		; There is drum?
	BMI @@4		; No, jump
	MVI _music_s4,R1
	       		; 1 - Strong
	BNE @@5
	CMPI #3,R1
	BGE @@12
@@10:	MVII #5,R0
	MVO R0,_music_noise
	CALL _activate_drum
	B @@12

@@5:	DECR R0		;2 - Short
	BNE @@11
	TSTR R1
	BNE @@12
	MVII #8,R0
	MVO R0,_music_noise
	CALL _activate_drum
	B @@12

@@11:	;DECR R0	; 3 - Rolling
	;BNE @@12
	CMPI #2,R1
	BLT @@10
	MVI _music_t,R0
	SLR R0,1
	CMPR R0,R1
	BLT @@12
	ADDI #2,R0
	CMPR R0,R1
	BLT @@10
	; Increase time for drum waveform
@@12:   INCR R1
	MVO R1,_music_s4

@@4:
    IF intybasic_music_ecs
	;
	; Construct main voice
	;
	MVI _music_n5,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@23	; No, jump
	MVI _music_s5,R1
	MVI _music_i5,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music2_freq10	; Note in voice A
	SWAP R3
	MVO R3,_music2_freq11
	MVO R1,_music2_vol1
	; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@24
	SUBI #$08,R0
@@24:	MVO R0,_music_s5

@@23:	MVI _music_n6,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@25		; No, jump
	MVI _music_s6,R1
	MVI _music_i6,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music2_freq20	; Note in voice B
	SWAP R3
	MVO R3,_music2_freq21
	MVO R1,_music2_vol2
	; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@26
	SUBI #$08,R0
@@26:	MVO R0,_music_s6

@@25:	MVI _music_n7,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@27		; No, jump
	MVI _music_s7,R1
	MVI _music_i7,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music2_freq30	; Note in voice C
	SWAP R3
	MVO R3,_music2_freq31
	MVO R1,_music2_vol3
	; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@28
	SUBI #$08,R0
@@28:	MVO R0,_music_s7

@@27:	MVI _music_n8,R0	; Read drum
	DECR R0		; There is drum?
	BMI @@0		; No, jump
	MVI _music_s8,R1
	       		; 1 - Strong
	BNE @@29
	CMPI #3,R1
	BGE @@31
@@32:	MVII #5,R0
	MVO R0,_music2_noise
	CALL _activate_drum_ecs
	B @@31

@@29:	DECR R0		;2 - Short
	BNE @@30
	TSTR R1
	BNE @@31
	MVII #8,R0
	MVO R0,_music2_noise
	CALL _activate_drum_ecs
	B @@31

@@30:	;DECR R0	; 3 - Rolling
	;BNE @@31
	CMPI #2,R1
	BLT @@32
	MVI _music_t,R0
	SLR R0,1
	CMPR R0,R1
	BLT @@31
	ADDI #2,R0
	CMPR R0,R1
	BLT @@32
	; Increase time for drum waveform
@@31:	INCR R1
	MVO R1,_music_s8

    ENDI
@@0:	RETURN
	ENDP

	;
	; Translates note number to frequency
	; R3 = Note
	; R1 = Position in waveform for instrument
	; R2 = Instrument
	;
_note2freq:	PROC
	ADD _music_table,R3
	MVI@ R3,R3
	SWAP R2
	BEQ _piano_instrument
	RLC R2,1
	BNC _clarinet_instrument
	BPL _flute_instrument
;	BMI _bass_instrument
	ENDP

	;
	; Generates a bass
	;
_bass_instrument:	PROC
	SLL R3,2	; Lower 2 octaves
	ADDI #_bass_volume,R1
	MVI@ R1,R1	; Bass effect
    IF intybasic_music_volume
	B _global_volume
    ELSE
	JR R5
    ENDI
	ENDP

_bass_volume:	PROC
	DECLE 12,13,14,14,13,12,12,12
	DECLE 11,11,12,12,11,11,12,12
	DECLE 11,11,12,12,11,11,12,12
	ENDP

	;
	; Generates a piano
	; R3 = Frequency
	; R1 = Waveform position
	;
	; Output:
	; R3 = Frequency.
	; R1 = Volume.
	;
_piano_instrument:	PROC
	ADDI #_piano_volume,R1
	MVI@ R1,R1
    IF intybasic_music_volume
	B _global_volume
    ELSE
	JR R5
    ENDI
	ENDP

_piano_volume:	PROC
	DECLE 14,13,13,12,12,11,11,10
	DECLE 10,9,9,8,8,7,7,6
	DECLE 6,6,7,7,6,6,5,5
	ENDP

	;
	; Generate a clarinet
	; R3 = Frequency
	; R1 = Waveform position
	;
	; Output:
	; R3 = Frequency
	; R1 = Volume
	;
_clarinet_instrument:	PROC
	ADDI #_clarinet_vibrato,R1
	ADD@ R1,R3
	CLRC
	RRC R3,1	; Duplicates frequency
	ADCR R3
	ADDI #_clarinet_volume-_clarinet_vibrato,R1
	MVI@ R1,R1
    IF intybasic_music_volume
	B _global_volume
    ELSE
	JR R5
    ENDI
	ENDP

_clarinet_vibrato:	PROC
	DECLE 0,0,0,0
	DECLE -2,-4,-2,0
	DECLE 2,4,2,0
	DECLE -2,-4,-2,0
	DECLE 2,4,2,0
	DECLE -2,-4,-2,0
	ENDP

_clarinet_volume:	PROC
	DECLE 13,14,14,13,13,12,12,12
	DECLE 11,11,11,11,12,12,12,12
	DECLE 11,11,11,11,12,12,12,12
	ENDP

	;
	; Generates a flute
	; R3 = Frequency
	; R1 = Waveform position
	;
	; Output:
	; R3 = Frequency
	; R1 = Volume
	;
_flute_instrument:	PROC
	ADDI #_flute_vibrato,R1
	ADD@ R1,R3
	ADDI #_flute_volume-_flute_vibrato,R1
	MVI@ R1,R1
    IF intybasic_music_volume
	B _global_volume
    ELSE
	JR R5
    ENDI
	ENDP

_flute_vibrato:	PROC
	DECLE 0,0,0,0
	DECLE 0,1,2,1
	DECLE 0,1,2,1
	DECLE 0,1,2,1
	DECLE 0,1,2,1
	DECLE 0,1,2,1
	ENDP
		 
_flute_volume:	PROC
	DECLE 10,12,13,13,12,12,12,12
	DECLE 11,11,11,11,10,10,10,10
	DECLE 11,11,11,11,10,10,10,10
	ENDP

    IF intybasic_music_volume

_global_volume:	PROC
	MVI _music_vol,R2
	ANDI #$0F,R2
	SLL R2,2
	SLL R2,2
	ADDR R1,R2
	ADDI #@@table,R2
	MVI@ R2,R1
	JR R5

@@table:
	DECLE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	DECLE 0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1
	DECLE 0,0,0,0,1,1,1,1,1,1,1,2,2,2,2,2
	DECLE 0,0,0,1,1,1,1,1,2,2,2,2,2,3,3,3
	DECLE 0,0,1,1,1,1,2,2,2,2,3,3,3,4,4,4
	DECLE 0,0,1,1,1,2,2,2,3,3,3,4,4,4,5,5
	DECLE 0,0,1,1,2,2,2,3,3,4,4,4,5,5,6,6
	DECLE 0,1,1,1,2,2,3,3,4,4,5,5,6,6,7,7
	DECLE 0,1,1,2,2,3,3,4,4,5,5,6,6,7,8,8
	DECLE 0,1,1,2,2,3,4,4,5,5,6,7,7,8,8,9
	DECLE 0,1,1,2,3,3,4,5,5,6,7,7,8,9,9,10
	DECLE 0,1,2,2,3,4,4,5,6,7,7,8,9,10,10,11
	DECLE 0,1,2,2,3,4,5,6,6,7,8,9,10,10,11,12
	DECLE 0,1,2,3,4,4,5,6,7,8,9,10,10,11,12,13
	DECLE 0,1,2,3,4,5,6,7,8,8,9,10,11,12,13,14
	DECLE 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15

	ENDP

    ENDI

    IF intybasic_music_ecs
	;
	; Emits sound for ECS
	;
_emit_sound_ecs:	PROC
	MOVR R5,R1
	MVI _music_mode,R2
	SARC R2,1
	BEQ @@6
	MVII #_music2_freq10,R4
	MVII #$00F0,R5
	B _emit_sound.0

@@6:	JR R1

	ENDP

    ENDI

	;
	; Emits sound
	;
_emit_sound:	PROC
	MOVR R5,R1
	MVI _music_mode,R2
	SARC R2,1
	BEQ @@6
	MVII #_music_freq10,R4
	MVII #$01F0,R5
@@0:
	MVI@ R4,R0
	MVO@ R0,R5	; $01F0 - Channel A Period (Low 8 bits of 12)
	MVI@ R4,R0
	MVO@ R0,R5	; $01F1 - Channel B Period (Low 8 bits of 12)
	DECR R2
	BEQ @@1
	MVI@ R4,R0	
	MVO@ R0,R5	; $01F2 - Channel C Period (Low 8 bits of 12)
	INCR R5		; Avoid $01F3 - Enveloped Period (Low 8 bits of 16)
	MVI@ R4,R0
	MVO@ R0,R5	; $01F4 - Channel A Period (High 4 bits of 12)
	MVI@ R4,R0
	MVO@ R0,R5	; $01F5 - Channel B Period (High 4 bits of 12)
	MVI@ R4,R0
	MVO@ R0,R5	; $01F6 - Channel C Period (High 4 bits of 12)
	INCR R5		; Avoid $01F7 - Envelope Period (High 8 bits of 16)
	BC @@2		; Jump if playing with drums
	ADDI #2,R4
	ADDI #3,R5
	B @@3

@@2:	MVI@ R4,R0
	MVO@ R0,R5	; $01F8 - Enable Noise/Tone (bits 3-5 Noise : 0-2 Tone)
	MVI@ R4,R0	
	MVO@ R0,R5	; $01F9 - Noise Period (5 bits)
	INCR R5		; Avoid $01FA - Envelope Type (4 bits)
@@3:	MVI@ R4,R0
	MVO@ R0,R5	; $01FB - Channel A Volume
	MVI@ R4,R0
	MVO@ R0,R5	; $01FC - Channel B Volume
	MVI@ R4,R0
	MVO@ R0,R5	; $01FD - Channel C Volume
	JR R1

@@1:	INCR R4		
	INCR R5		; Avoid $01F2 and $01F3
	INCR R5		; Cannot use ADDI
	MVI@ R4,R0
	MVO@ R0,R5	; $01F4 - Channel A Period (High 4 bits of 12)
	MVI@ R4,R0
	MVO@ R0,R5	; $01F5 - Channel B Period (High 4 bits of 12)
	INCR R4
	INCR R5		; Avoid $01F6 and $01F7
	INCR R5		; Cannot use ADDI
	BC @@4		; Jump if playing with drums
	ADDI #2,R4
	ADDI #3,R5
	B @@5

@@4:	MVI@ R4,R0
	MVO@ R0,R5	; $01F8 - Enable Noise/Tone (bits 3-5 Noise : 0-2 Tone)
	MVI@ R4,R0
	MVO@ R0,R5	; $01F9 - Noise Period (5 bits)
	INCR R5		; Avoid $01FA - Envelope Type (4 bits)
@@5:	MVI@ R4,R0
	MVO@ R0,R5	; $01FB - Channel A Volume
	MVI@ R4,R0
	MVO@ R0,R5	; $01FC - Channel B Volume
@@6:	JR R1
	ENDP

	;
	; Activates drum
	;
_activate_drum:	PROC
    IF intybasic_music_volume
	BEGIN
    ENDI
	MVI _music_mode,R2
	SARC R2,1	; PLAY NO DRUMS?
	BNC @@0		; Yes, jump
	MVI _music_vol1,R0
	TSTR R0
	BNE @@1
	MVII #11,R1
    IF intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music_vol1
	MVI _music_mix,R0
	ANDI #$F6,R0
	XORI #$01,R0
	MVO R0,_music_mix
    IF intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@1:    MVI _music_vol2,R0
	TSTR R0
	BNE @@2
	MVII #11,R1
    IF intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music_vol2
	MVI _music_mix,R0
	ANDI #$ED,R0
	XORI #$02,R0
	MVO R0,_music_mix
    IF intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@2:    DECR R2		; PLAY SIMPLE?
	BEQ @@3		; Yes, jump
	MVI _music_vol3,R0
	TSTR R0
	BNE @@3
	MVII #11,R1
    IF intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music_vol3
	MVI _music_mix,R0
	ANDI #$DB,R0
	XORI #$04,R0
	MVO R0,_music_mix
    IF intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@3:    MVI _music_mix,R0
	ANDI #$EF,R0
	MVO R0,_music_mix
@@0:	
    IF intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

	ENDP

    IF intybasic_music_ecs
	;
	; Activates drum
	;
_activate_drum_ecs:	PROC
    IF intybasic_music_volume
	BEGIN
    ENDI
	MVI _music_mode,R2
	SARC R2,1	; PLAY NO DRUMS?
	BNC @@0		; Yes, jump
	MVI _music2_vol1,R0
	TSTR R0
	BNE @@1
	MVII #11,R1
    IF intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music2_vol1
	MVI _music2_mix,R0
	ANDI #$F6,R0
	XORI #$01,R0
	MVO R0,_music2_mix
    IF intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@1:    MVI _music2_vol2,R0
	TSTR R0
	BNE @@2
	MVII #11,R1
    IF intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music2_vol2
	MVI _music2_mix,R0
	ANDI #$ED,R0
	XORI #$02,R0
	MVO R0,_music2_mix
    IF intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@2:    DECR R2		; PLAY SIMPLE?
	BEQ @@3		; Yes, jump
	MVI _music2_vol3,R0
	TSTR R0
	BNE @@3
	MVII #11,R1
    IF intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music2_vol3
	MVI _music2_mix,R0
	ANDI #$DB,R0
	XORI #$04,R0
	MVO R0,_music2_mix
    IF intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@3:    MVI _music2_mix,R0
	ANDI #$EF,R0
	MVO R0,_music2_mix
@@0:	
    IF intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

	ENDP

    ENDI

    ENDI
    
    IF intybasic_numbers

;;==========================================================================;;
;; IntyBASIC SDK Library: print-num.asm                                     ;;
;;--------------------------------------------------------------------------;;
;;  This library is based on a BCD display algorithm originally proposed by ;;
;;  Mark Ball (GroovyBee), with additional optimizations suggested by Joe   ;;
;;  Zbiciak (intvnut) in the AtariAge Intellivision Programming forum.  It  ;;
;;  is a novel implementation of Joe's PRNUM16() routine, intended to       ;;
;;  execute much faster.                                                    ;;
;;                                                                          ;;
;;  The algorithm was then further optimized and adapted for the            ;;
;;  P-Machinery framework by unrolling the loops, etc.  It was then         ;;
;;  modified once again to support the original PRNUM16() functionality and ;;
;;  invocation interface, and serve as a drop-in replacement in the         ;;
;;  IntyBASIC run-time framework.                                           ;;
;;--------------------------------------------------------------------------;;
;;      The file is placed into the public domain by its author.            ;;
;;      All copyrights are hereby relinquished on the routines and data in  ;;
;;      this file.  -- James Pujals (DZ-Jay), 2024                          ;;
;;==========================================================================;;

;; ======================================================================== ;;
;;  PRINT_NUM16_PAD                                                         ;;
;;  Procedure to print an unsigned 16-bit value as a decimal number, left-  ;;
;;  or right-justified, with optional pre-padding.  It also supports        ;;
;;  variable field widths.                                                  ;;
;;                                                                          ;;
;;  DESCRIPTION:                                                            ;;
;;      Depending on the entry point invoked, the number is printed in      ;;
;;      either left- or right-justified format.  Right-justified numbers    ;;
;;      are padded with leading zeros or blanks to fit the given width.     ;;
;;      Left-justified numbers are not padded, and the field width argument ;;
;;      is ignored.                                                         ;;
;;                                                                          ;;
;;      Examples:                                                           ;;
;;          Routine               Value      Field       Output             ;;
;;          ------------------  ---------  ----------  ----------           ;;
;;          PRINT_NUM16_PAD.l      123        N/A       "123"               ;;
;;          PRINT_NUM16_PAD.b      123         3        "123"               ;;
;;          PRINT_NUM16_PAD.b      123         4        " 123"              ;;
;;          PRINT_NUM16_PAD.b      123         7        "    123"           ;;
;;          PRINT_NUM16_PAD.z      123         3        "123"               ;;
;;          PRINT_NUM16_PAD.z      123         4        "0123"              ;;
;;          PRINT_NUM16_PAD.z      123         7        "0000123"           ;;
;;                                                                          ;;
;;      After doing some housekeeping preparations for the variant invoked, ;;
;;      the routine then identifies the lowest power-of-10 that is higher   ;;
;;      than the input number.  It then proceeds to divide the number by    ;;
;;      decreasing powers-of-ten to derive each digit to print, in          ;;
;;      succession.  All divisions are made by repeated subtraction.        ;;
;;                                                                          ;;
;;      The routine does not access any RAM (other than the stack), or      ;;
;;      depend on any external resources, so it is fully re-entrant.        ;;
;;                                                                          ;;
;;  CODESIZE:                                                               ;;
;;      132 words, including jump tables and unrolled loops.                ;;
;;                                                                          ;;
;; ------------------------------------------------------------------------ ;;
;;                                                                          ;;
;;  There are three entry points to this procedure:                         ;;
;;      PRINT_NUM16_PAD.l       Prints a left-justified 16-bit number.      ;;
;;                                                                          ;;
;;      PRINT_NUM16_PAD.z       Prints a right-justified 16-bit number,     ;;
;;                              padded with zeros.                          ;;
;;                                                                          ;;
;;      PRINT_NUM16_PAD.b       Prints a right-justified 16-bit number,     ;;
;;                              padded with blanks.                         ;;
;;                                                                          ;;
;;  NOTE:   The field width must be equal to, or wider than, the decimal    ;;
;;          number width, or else the output will be corrupted.  Also, the  ;;
;;          format word must be a valid BACKTAB color value.  If the format ;;
;;          includes any other bits, it may corrupt the output.             ;;
;;                                                                          ;;
;;          The routine also supports field widths larger than 5 positions, ;;
;;          padding them with zeros or blanks, as necessary.  However, no   ;;
;;          bounds-checking is performed, so it is possible to attemp to    ;;
;;          print beyond the BACKTAB bounds.                                ;;
;;                                                                          ;;
;;  INPUT for PRINT_NUM16_PAD (all variations)                              ;;
;;      R0      16-bit numeric value.                                       ;;
;;      R2      Print field width.                                          ;;
;;      R3      BACKTAB format word for prefix char.                        ;;
;;      R4      Pointer to BACKTAB destination.                             ;;
;;      R5      Pointer to invocation record, followed by return address.   ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      R0      Trashed.                                                    ;;
;;      R1      Trashed.                                                    ;;
;;      R2      Trashed.                                                    ;;
;;      R3      Trashed (color).                                            ;;
;;      R4      Trashed  (1 word beyond end of number string in BACKTAB).   ;;
;; ======================================================================== ;;
PRNUM16		PROC
.max_width      QSET    5
.chr_clrmask    QSET    $FE07
.chr_offset     QSET    (1 SHL 3)
.digit_base     QSET    ('0' - ' ')
.lzero          QSET    (((.digit_base -  0) SHL 3) AND $FFFF)
.lzero_even     QSET    (((.digit_base -  1) SHL 3) AND $FFFF)
.lzero_odd      QSET    (((.digit_base + 10) SHL 3) AND $FFFF)

                ; --------------------------------------
                ; Left-Justified (No Padding)
                ; --------------------------------------
@@l:            BEGIN

                MVII    #.chr_offset,           R5      ; Initialize character advancement term

                ; --------------------------------------
                ; Find highest power of 10 to determine
                ; entry point to digits printing loop.
                ;   (The loop is unrolled for speed.)
                ;
                ;   pow = 4;
                ;   do {
                ;       if (val >= (10 ** pow--)) {
                ;           break;
                ;       }
                ;   } while (pow >= 0);
                ; --------------------------------------
@@__l_10_4:     CMPI    #10000, R0                      ;   if (val >= (10 ** pow--))
                BC      @@__pow4                        ;       break;

@@__l_10_3:     CMPI    #1000,  R0                      ;   if (val >= (10 ** pow--))
                BC      @@__fix_10_3                    ;       break;

@@__l_10_2:     CMPI    #100,   R0                      ;   if (val >= (10 ** pow--))
                BC      @@__pow2                        ;       break;

@@__l_10_1:     CMPI    #10,    R0                      ;   if (val >= (10 ** pow--))
                BC      @@__fix_10_1                    ;       break;

@@__l_10_0:     TSTR    R0                              ;   if (val != 0)
                BNZE    @@__pow0                        ;       break;
                B       @@__zero

                ; --------------------------------------
                ; Right-Justified: Zero-Padded
                ; --------------------------------------
@@z:            XORI    #.lzero,R3                      ; Initialize prefix to character "0" (zero).

                ; --------------------------------------
                ; Right-Justified: Blank-Padded
                ; --------------------------------------
@@b:            MOVR    R2,     R1                      ; \
                SUBI    #5,     R1                      ;  > Is field size greater than max width?
                BLE     @@__padding                     ; /     No:  Just pad field based on magnitude.
                                                        ;       Yes: Pad field until we reach max width.
                ; --------------------------------------
                ; Force padding until we reach max width
                ;   while (overflow > 0) {
                ;       print_at(prefix, pos++);
                ;       overflow--;
                ;   }
                ; --------------------------------------
                SUBR    R1,     R2                      ; R1 = overflow; R2 = max width
@@__pad_ovr:    MVO@    R3,     R4                      ; Print padding character ...
                DECR    R1                              ; \_ Is overflow done?
                BNZE    @@__pad_ovr                     ; /     No:  Continue padding.

@@__padding:    BEGIN

                MOVR    R3,     R1
                ANDI    #.chr_clrmask,          R3      ; Clear out prefix character
                MVII    #.chr_offset,           R5      ; Initialize character advancement term

                ADDI    #(@@__switch - 1),      R2      ; \_ Jump to entry point based on field width
                MVI@    R2,     PC                      ; /

@@__switch:     DECLE   @@__p_10_0  ; Width = 1: 10^0
                DECLE   @@__p_10_1  ; Width = 2: 10^1
                DECLE   @@__p_10_2  ; Width = 3: 10^2
                DECLE   @@__p_10_3  ; Width = 4: 10^3
                DECLE   @@__p_10_4  ; Width = 5: 10^4

                ; --------------------------------------
                ; Pad the field with prefix character
                ;   (The loop is unrolled for speed.)
                ;
                ;   pow = 4;  // 10^0..10^4
                ;   do {
                ;       if (val >= (10 ** pow--)) {
                ;           break;
                ;       }
                ;       print_at(prefix, pos++);
                ;   } while (pow >= 0);
                ; --------------------------------------
@@__p_10_4:     CMPI    #10000, R0                      ;   if (val >= (10 ** pow--))
                BC      @@__pow4                        ;       break;
                MVO@    R1,     R4                      ;   print_at(prefix, pos++);

@@__p_10_3:     CMPI    #1000,  R0                      ;   if (val >= (10 ** pow--))
                BC      @@__fix_10_3                    ;       break;
                MVO@    R1,     R4                      ;   print_at(prefix, pos++);

@@__p_10_2:     CMPI    #100,   R0                      ;   if (val >= (10 ** pow--))
                BC      @@__pow2                        ;       break;
                MVO@    R1,     R4                      ;   print_at(prefix, pos++);

@@__p_10_1:     CMPI    #10,    R0                      ;   if (val >= (10 ** pow--))
                BC      @@__fix_10_1                    ;       break;
                MVO@    R1,     R4                      ;   print_at(prefix, pos++);

@@__p_10_0:     TSTR    R0                              ;   if (val != 0)
                BNZE    @@__pow0                        ;       break;

                ; --------------------------------------
                ; Special case for when value is zero
                ; --------------------------------------
@@__zero:       XORI    #.lzero,R3                      ; Prepare formatted zero
                MVO@    R3,     R4                      ;       print_at(zero, pos++);
                RETURN

                ; --------------------------------------
                ; Adjust value of odd powers, for direct
                ; entry into the PRINT_NUM16() routine.
                ; --------------------------------------
@@__fix_10_1:   SUBI    #100,   R0                      ; \_ Adjust value to jump into 10^1 block
                B       @@__pow1                        ; /

@@__fix_10_3:   SUBI    #10000, R0                      ; \_ Adjust value to jump into 10^3 block
                B       @@__pow3                        ; /

                ; --------------------------------------
                ; Print decimal digits
                ; --------------------------------------

                ; 10^4: 10,000
                ; --------------------------------------
@@__pow4:       MVII    #.lzero_even,           R1      ; Prep GROM character.
                XORR    R3,     R1                      ; Mix in the STIC colors.
                MVII    #10000, R2

@@__d_10_4:     ADDR    R5,     R1
                SUBR    R2,     R0
                BC      @@__d_10_4
                MVO@    R1,     R4                      ; Output to BACKTAB screen buffer.

                ; 10^3: 1,000
                ; --------------------------------------
@@__pow3:       MVII    #.lzero_odd,            R1      ; Prep GROM character.
                XORR    R3,     R1                      ; Mix in the STIC colors.
                MVII    #1000,  R2

@@__d_10_3:     SUBR    R5,     R1
                ADDR    R2,     R0
                BNC     @@__d_10_3
                MVO@    R1,     R4                      ; Output to BACKTAB screen buffer.

                ; 10^2: 100
                ; --------------------------------------
@@__pow2:       MVII    #.lzero_even,           R1      ; Prep GROM character.
                XORR    R3,     R1                      ; Mix in the STIC colors.
                MVII    #100,   R2

@@__d_10_2:     ADDR    R5,     R1
                SUBR    R2,     R0
                BC      @@__d_10_2
                MVO@    R1,     R4                      ; Output to BACKTAB screen buffer.

                ; 10^1: 10
                ; --------------------------------------
@@__pow1:       MVII    #.lzero_odd,            R1      ; Prep GROM character.
                XORR    R3,     R1                      ; Mix in the STIC colors.
                MVII    #10,    R2

@@__d_10_1:     SUBR    R5,     R1
                ADDR    R2,     R0
                BNC     @@__d_10_1
                MVO@    R1,     R4                      ; Output to BACKTAB screen buffer.

                ; 10^0: 1
                ; --------------------------------------
@@__pow0:       ADDI    #.digit_base,           R0      ; Prep GROM character.
                SLL     R0,     2                       ; \
                SLL     R0,     1                       ;  > chr = ((chr << 3) ^ format);
                XORR    R3,     R0                      ; /
                MVO@    R0,     R4                      ; Output to BACKTAB screen buffer.

                ; All done!
                ; --------------------------------------
                RETURN

@@____size:     EQU     ($ - PRNUM16)
                ENDP

;; ======================================================================== ;;
;;  EOF: romseg-bs.mac                                                      ;;
;; ======================================================================== ;;

    ENDI

    IF intybasic_voice
;;==========================================================================;;
;;  SP0256-AL2 Allophones						   ;;
;;									  ;;
;;  This file contains the allophone set that was obtained from an	  ;;
;;  SP0256-AL2.  It is being provided for your convenience.		 ;;
;;									  ;;
;;  The directory "al2" contains a series of assembly files, each one       ;;
;;  containing a single allophone.  This series of files may be useful in   ;;
;;  situations where space is at a premium.				 ;;
;;									  ;;
;;  Consult the Archer SP0256-AL2 documentation (under doc/programming)     ;;
;;  for more information about SP0256-AL2's allophone library.	      ;;
;;									  ;;
;; ------------------------------------------------------------------------ ;;
;;									  ;;
;;  Copyright information:						  ;;
;;									  ;;
;;  The allophone data below was extracted from the SP0256-AL2 ROM image.   ;;
;;  The SP0256-AL2 allophones are NOT in the public domain, nor are they    ;;
;;  placed under the GNU General Public License.  This program is	   ;;
;;  distributed in the hope that it will be useful, but WITHOUT ANY	 ;;
;;  WARRANTY; without even the implied warranty of MERCHANTABILITY or       ;;
;;  FITNESS FOR A PARTICULAR PURPOSE.				       ;;
;;									  ;;
;;  Microchip, Inc. retains the copyright to the data and algorithms	;;
;;  contained in the SP0256-AL2.  This speech data is distributed with      ;;
;;  explicit permission from Microchip, Inc.  All such redistributions      ;;
;;  must retain this notice of copyright.				   ;;
;;									  ;;
;;  No copyright claims are made on this data by the author(s) of SDK1600.  ;;
;;  Please see http://spatula-city.org/~im14u2c/sp0256-al2/ for details.    ;;
;;									  ;;
;;==========================================================================;;

;; ------------------------------------------------------------------------ ;;
_AA:
    DECLE   _AA.end - _AA - 1
    DECLE   $0318, $014C, $016F, $02CE, $03AF, $015F, $01B1, $008E
    DECLE   $0088, $0392, $01EA, $024B, $03AA, $039B, $000F, $0000
_AA.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_AE1:
    DECLE   _AE1.end - _AE1 - 1
    DECLE   $0118, $038E, $016E, $01FC, $0149, $0043, $026F, $036E
    DECLE   $01CC, $0005, $0000
_AE1.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_AO:
    DECLE   _AO.end - _AO - 1
    DECLE   $0018, $010E, $016F, $0225, $00C6, $02C4, $030F, $0160
    DECLE   $024B, $0005, $0000
_AO.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_AR:
    DECLE   _AR.end - _AR - 1
    DECLE   $0218, $010C, $016E, $001E, $000B, $0091, $032F, $00DE
    DECLE   $018B, $0095, $0003, $0238, $0027, $01E0, $03E8, $0090
    DECLE   $0003, $01C7, $0020, $03DE, $0100, $0190, $01CA, $02AB
    DECLE   $00B7, $004A, $0386, $0100, $0144, $02B6, $0024, $0320
    DECLE   $0011, $0041, $01DF, $0316, $014C, $016E, $001E, $00C4
    DECLE   $02B2, $031E, $0264, $02AA, $019D, $01BE, $000B, $00F0
    DECLE   $006A, $01CE, $00D6, $015B, $03B5, $03E4, $0000, $0380
    DECLE   $0007, $0312, $03E8, $030C, $016D, $02EE, $0085, $03C2
    DECLE   $03EC, $0283, $024A, $0005, $0000
_AR.end:  ; 69 decles
;; ------------------------------------------------------------------------ ;;
_AW:
    DECLE   _AW.end - _AW - 1
    DECLE   $0010, $01CE, $016E, $02BE, $0375, $034F, $0220, $0290
    DECLE   $008A, $026D, $013F, $01D5, $0316, $029F, $02E2, $018A
    DECLE   $0170, $0035, $00BD, $0000, $0000
_AW.end:  ; 21 decles
;; ------------------------------------------------------------------------ ;;
_AX:
    DECLE   _AX.end - _AX - 1
    DECLE   $0218, $02CD, $016F, $02F5, $0386, $00C2, $00CD, $0094
    DECLE   $010C, $0005, $0000
_AX.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_AY:
    DECLE   _AY.end - _AY - 1
    DECLE   $0110, $038C, $016E, $03B7, $03B3, $02AF, $0221, $009E
    DECLE   $01AA, $01B3, $00BF, $02E7, $025B, $0354, $00DA, $017F
    DECLE   $018A, $03F3, $00AF, $02D5, $0356, $027F, $017A, $01FB
    DECLE   $011E, $01B9, $03E5, $029F, $025A, $0076, $0148, $0124
    DECLE   $003D, $0000
_AY.end:  ; 34 decles
;; ------------------------------------------------------------------------ ;;
_BB1:
    DECLE   _BB1.end - _BB1 - 1
    DECLE   $0318, $004C, $016C, $00FB, $00C7, $0144, $002E, $030C
    DECLE   $010E, $018C, $01DC, $00AB, $00C9, $0268, $01F7, $021D
    DECLE   $01B3, $0098, $0000
_BB1.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_BB2:
    DECLE   _BB2.end - _BB2 - 1
    DECLE   $00F4, $0046, $0062, $0200, $0221, $03E4, $0087, $016F
    DECLE   $02A6, $02B7, $0212, $0326, $0368, $01BF, $0338, $0196
    DECLE   $0002
_BB2.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_CH:
    DECLE   _CH.end - _CH - 1
    DECLE   $00F5, $0146, $0052, $0000, $032A, $0049, $0032, $02F2
    DECLE   $02A5, $0000, $026D, $0119, $0124, $00F6, $0000
_CH.end:  ; 15 decles
;; ------------------------------------------------------------------------ ;;
_DD1:
    DECLE   _DD1.end - _DD1 - 1
    DECLE   $0318, $034C, $016E, $0397, $01B9, $0020, $02B1, $008E
    DECLE   $0349, $0291, $01D8, $0072, $0000
_DD1.end:  ; 13 decles
;; ------------------------------------------------------------------------ ;;
_DD2:
    DECLE   _DD2.end - _DD2 - 1
    DECLE   $00F4, $00C6, $00F2, $0000, $0129, $00A6, $0246, $01F3
    DECLE   $02C6, $02B7, $028E, $0064, $0362, $01CF, $0379, $01D5
    DECLE   $0002
_DD2.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_DH1:
    DECLE   _DH1.end - _DH1 - 1
    DECLE   $0018, $034F, $016D, $030B, $0306, $0363, $017E, $006A
    DECLE   $0164, $019E, $01DA, $00CB, $00E8, $027A, $03E8, $01D7
    DECLE   $0173, $00A1, $0000
_DH1.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_DH2:
    DECLE   _DH2.end - _DH2 - 1
    DECLE   $0119, $034C, $016D, $030B, $0306, $0363, $017E, $006A
    DECLE   $0164, $019E, $01DA, $00CB, $00E8, $027A, $03E8, $01D7
    DECLE   $0173, $00A1, $0000
_DH2.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_EH:
    DECLE   _EH.end - _EH - 1
    DECLE   $0218, $02CD, $016F, $0105, $014B, $0224, $02CF, $0274
    DECLE   $014C, $0005, $0000
_EH.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_EL:
    DECLE   _EL.end - _EL - 1
    DECLE   $0118, $038D, $016E, $011C, $008B, $03D2, $030F, $0262
    DECLE   $006C, $019D, $01CC, $022B, $0170, $0078, $03FE, $0018
    DECLE   $0183, $03A3, $010D, $016E, $012E, $00C6, $00C3, $0300
    DECLE   $0060, $000D, $0005, $0000
_EL.end:  ; 28 decles
;; ------------------------------------------------------------------------ ;;
_ER1:
    DECLE   _ER1.end - _ER1 - 1
    DECLE   $0118, $034C, $016E, $001C, $0089, $01C3, $034E, $03E6
    DECLE   $00AB, $0095, $0001, $0000, $03FC, $0381, $0000, $0188
    DECLE   $01DA, $00CB, $00E7, $0048, $03A6, $0244, $016C, $01A8
    DECLE   $03E4, $0000, $0002, $0001, $00FC, $01DA, $02E4, $0000
    DECLE   $0002, $0008, $0200, $0217, $0164, $0000, $000E, $0038
    DECLE   $0014, $01EA, $0264, $0000, $0002, $0048, $01EC, $02F1
    DECLE   $03CC, $016D, $021E, $0048, $00C2, $034E, $036A, $000D
    DECLE   $008D, $000B, $0200, $0047, $0022, $03A8, $0000, $0000
_ER1.end:  ; 64 decles
;; ------------------------------------------------------------------------ ;;
_ER2:
    DECLE   _ER2.end - _ER2 - 1
    DECLE   $0218, $034C, $016E, $001C, $0089, $01C3, $034E, $03E6
    DECLE   $00AB, $0095, $0001, $0000, $03FC, $0381, $0000, $0190
    DECLE   $01D8, $00CB, $00E7, $0058, $01A6, $0244, $0164, $02A9
    DECLE   $0024, $0000, $0000, $0007, $0201, $02F8, $02E4, $0000
    DECLE   $0002, $0001, $00FC, $02DA, $0024, $0000, $0002, $0008
    DECLE   $0200, $0217, $0024, $0000, $000E, $0038, $0014, $03EA
    DECLE   $03A4, $0000, $0002, $0048, $01EC, $03F1, $038C, $016D
    DECLE   $021E, $0048, $00C2, $034E, $036A, $000D, $009D, $0003
    DECLE   $0200, $0047, $0022, $03A8, $0000, $0000
_ER2.end:  ; 70 decles
;; ------------------------------------------------------------------------ ;;
_EY:
    DECLE   _EY.end - _EY - 1
    DECLE   $0310, $038C, $016E, $02A7, $00BB, $0160, $0290, $0094
    DECLE   $01CA, $03A9, $00C1, $02D7, $015B, $01D4, $03CE, $02FF
    DECLE   $00EA, $03E7, $0041, $0277, $025B, $0355, $03C9, $0103
    DECLE   $02EA, $03E4, $003F, $0000
_EY.end:  ; 28 decles
;; ------------------------------------------------------------------------ ;;
_FF:
    DECLE   _FF.end - _FF - 1
    DECLE   $0119, $03C8, $0000, $00A7, $0094, $0138, $01C6, $0000
_FF.end:  ; 8 decles
;; ------------------------------------------------------------------------ ;;
_GG1:
    DECLE   _GG1.end - _GG1 - 1
    DECLE   $00F4, $00C6, $00C2, $0200, $0015, $03FE, $0283, $01FD
    DECLE   $01E6, $00B7, $030A, $0364, $0331, $017F, $033D, $0215
    DECLE   $0002
_GG1.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_GG2:
    DECLE   _GG2.end - _GG2 - 1
    DECLE   $00F4, $0106, $0072, $0300, $0021, $0308, $0039, $0173
    DECLE   $00C6, $00B7, $037E, $03A3, $0319, $0177, $0036, $0217
    DECLE   $0002
_GG2.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_GG3:
    DECLE   _GG3.end - _GG3 - 1
    DECLE   $00F8, $0146, $00F2, $0100, $0132, $03A8, $0055, $01F5
    DECLE   $00A6, $02B7, $0291, $0326, $0368, $0167, $023A, $01C6
    DECLE   $0002
_GG3.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_HH1:
    DECLE   _HH1.end - _HH1 - 1
    DECLE   $0218, $01C9, $0000, $0095, $0127, $0060, $01D6, $0213
    DECLE   $0002, $01AE, $033E, $01A0, $03C4, $0122, $0001, $0218
    DECLE   $01E4, $03FD, $0019, $0000
_HH1.end:  ; 20 decles
;; ------------------------------------------------------------------------ ;;
_HH2:
    DECLE   _HH2.end - _HH2 - 1
    DECLE   $0218, $00CB, $0000, $0086, $000F, $0240, $0182, $031A
    DECLE   $02DB, $0008, $0293, $0067, $00BD, $01E0, $0092, $000C
    DECLE   $0000
_HH2.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_IH:
    DECLE   _IH.end - _IH - 1
    DECLE   $0118, $02CD, $016F, $0205, $0144, $02C3, $00FE, $031A
    DECLE   $000D, $0005, $0000
_IH.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_IY:
    DECLE   _IY.end - _IY - 1
    DECLE   $0318, $02CC, $016F, $0008, $030B, $01C3, $0330, $0178
    DECLE   $002B, $019D, $01F6, $018B, $01E1, $0010, $020D, $0358
    DECLE   $015F, $02A4, $02CC, $016F, $0109, $030B, $0193, $0320
    DECLE   $017A, $034C, $009C, $0017, $0001, $0200, $03C1, $0020
    DECLE   $00A7, $001D, $0001, $0104, $003D, $0040, $01A7, $01CA
    DECLE   $018B, $0160, $0078, $01F6, $0343, $01C7, $0090, $0000
_IY.end:  ; 48 decles
;; ------------------------------------------------------------------------ ;;
_JH:
    DECLE   _JH.end - _JH - 1
    DECLE   $0018, $0149, $0001, $00A4, $0321, $0180, $01F4, $039A
    DECLE   $02DC, $023C, $011A, $0047, $0200, $0001, $018E, $034E
    DECLE   $0394, $0356, $02C1, $010C, $03FD, $0129, $00B7, $01BA
    DECLE   $0000
_JH.end:  ; 25 decles
;; ------------------------------------------------------------------------ ;;
_KK1:
    DECLE   _KK1.end - _KK1 - 1
    DECLE   $00F4, $00C6, $00D2, $0000, $023A, $03E0, $02D1, $02E5
    DECLE   $0184, $0200, $0041, $0210, $0188, $00C5, $0000
_KK1.end:  ; 15 decles
;; ------------------------------------------------------------------------ ;;
_KK2:
    DECLE   _KK2.end - _KK2 - 1
    DECLE   $021D, $023C, $0211, $003C, $0180, $024D, $0008, $032B
    DECLE   $025B, $002D, $01DC, $01E3, $007A, $0000
_KK2.end:  ; 14 decles
;; ------------------------------------------------------------------------ ;;
_KK3:
    DECLE   _KK3.end - _KK3 - 1
    DECLE   $00F7, $0046, $01D2, $0300, $0131, $006C, $006E, $00F1
    DECLE   $00E4, $0000, $025A, $010D, $0110, $01F9, $014A, $0001
    DECLE   $00B5, $01A2, $00D8, $01CE, $0000
_KK3.end:  ; 21 decles
;; ------------------------------------------------------------------------ ;;
_LL:
    DECLE   _LL.end - _LL - 1
    DECLE   $0318, $038C, $016D, $029E, $0333, $0260, $0221, $0294
    DECLE   $01C4, $0299, $025A, $00E6, $014C, $012C, $0031, $0000
_LL.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_MM:
    DECLE   _MM.end - _MM - 1
    DECLE   $0210, $034D, $016D, $03F5, $00B0, $002E, $0220, $0290
    DECLE   $03CE, $02B6, $03AA, $00F3, $00CF, $015D, $016E, $0000
_MM.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_NG1:
    DECLE   _NG1.end - _NG1 - 1
    DECLE   $0118, $03CD, $016E, $00DC, $032F, $01BF, $01E0, $0116
    DECLE   $02AB, $029A, $0358, $01DB, $015B, $01A7, $02FD, $02B1
    DECLE   $03D2, $0356, $0000
_NG1.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_NN1:
    DECLE   _NN1.end - _NN1 - 1
    DECLE   $0318, $03CD, $016C, $0203, $0306, $03C3, $015F, $0270
    DECLE   $002A, $009D, $000D, $0248, $01B4, $0120, $01E1, $00C8
    DECLE   $0003, $0040, $0000, $0080, $015F, $0006, $0000
_NN1.end:  ; 23 decles
;; ------------------------------------------------------------------------ ;;
_NN2:
    DECLE   _NN2.end - _NN2 - 1
    DECLE   $0018, $034D, $016D, $0203, $0306, $03C3, $015F, $0270
    DECLE   $002A, $0095, $0003, $0248, $01B4, $0120, $01E1, $0090
    DECLE   $000B, $0040, $0000, $0080, $015F, $019E, $01F6, $028B
    DECLE   $00E0, $0266, $03F6, $01D8, $0143, $01A8, $0024, $00C0
    DECLE   $0080, $0000, $01E6, $0321, $0024, $0260, $000A, $0008
    DECLE   $03FE, $0000, $0000
_NN2.end:  ; 43 decles
;; ------------------------------------------------------------------------ ;;
_OR2:
    DECLE   _OR2.end - _OR2 - 1
    DECLE   $0218, $018C, $016D, $02A6, $03AB, $004F, $0301, $0390
    DECLE   $02EA, $0289, $0228, $0356, $01CF, $02D5, $0135, $007D
    DECLE   $02B5, $02AF, $024A, $02E2, $0153, $0167, $0333, $02A9
    DECLE   $02B3, $039A, $0351, $0147, $03CD, $0339, $02DA, $0000
_OR2.end:  ; 32 decles
;; ------------------------------------------------------------------------ ;;
_OW:
    DECLE   _OW.end - _OW - 1
    DECLE   $0310, $034C, $016E, $02AE, $03B1, $00CF, $0304, $0192
    DECLE   $018A, $022B, $0041, $0277, $015B, $0395, $03D1, $0082
    DECLE   $03CE, $00B6, $03BB, $02DA, $0000
_OW.end:  ; 21 decles
;; ------------------------------------------------------------------------ ;;
_OY:
    DECLE   _OY.end - _OY - 1
    DECLE   $0310, $014C, $016E, $02A6, $03AF, $00CF, $0304, $0192
    DECLE   $03CA, $01A8, $007F, $0155, $02B4, $027F, $00E2, $036A
    DECLE   $031F, $035D, $0116, $01D5, $02F4, $025F, $033A, $038A
    DECLE   $014F, $01B5, $03D5, $0297, $02DA, $03F2, $0167, $0124
    DECLE   $03FB, $0001
_OY.end:  ; 34 decles
;; ------------------------------------------------------------------------ ;;
_PA1:
    DECLE   _PA1.end - _PA1 - 1
    DECLE   $00F1, $0000
_PA1.end:  ; 2 decles
;; ------------------------------------------------------------------------ ;;
_PA2:
    DECLE   _PA2.end - _PA2 - 1
    DECLE   $00F4, $0000
_PA2.end:  ; 2 decles
;; ------------------------------------------------------------------------ ;;
_PA3:
    DECLE   _PA3.end - _PA3 - 1
    DECLE   $00F7, $0000
_PA3.end:  ; 2 decles
;; ------------------------------------------------------------------------ ;;
_PA4:
    DECLE   _PA4.end - _PA4 - 1
    DECLE   $00FF, $0000
_PA4.end:  ; 2 decles
;; ------------------------------------------------------------------------ ;;
_PA5:
    DECLE   _PA5.end - _PA5 - 1
    DECLE   $031D, $003F, $0000
_PA5.end:  ; 3 decles
;; ------------------------------------------------------------------------ ;;
_PP:
    DECLE   _PP.end - _PP - 1
    DECLE   $00FD, $0106, $0052, $0000, $022A, $03A5, $0277, $035F
    DECLE   $0184, $0000, $0055, $0391, $00EB, $00CF, $0000
_PP.end:  ; 15 decles
;; ------------------------------------------------------------------------ ;;
_RR1:
    DECLE   _RR1.end - _RR1 - 1
    DECLE   $0118, $01CD, $016C, $029E, $0171, $038E, $01E0, $0190
    DECLE   $0245, $0299, $01AA, $02E2, $01C7, $02DE, $0125, $00B5
    DECLE   $02C5, $028F, $024E, $035E, $01CB, $02EC, $0005, $0000
_RR1.end:  ; 24 decles
;; ------------------------------------------------------------------------ ;;
_RR2:
    DECLE   _RR2.end - _RR2 - 1
    DECLE   $0218, $03CC, $016C, $030C, $02C8, $0393, $02CD, $025E
    DECLE   $008A, $019D, $01AC, $02CB, $00BE, $0046, $017E, $01C2
    DECLE   $0174, $00A1, $01E5, $00E0, $010E, $0007, $0313, $0017
    DECLE   $0000
_RR2.end:  ; 25 decles
;; ------------------------------------------------------------------------ ;;
_SH:
    DECLE   _SH.end - _SH - 1
    DECLE   $0218, $0109, $0000, $007A, $0187, $02E0, $03F6, $0311
    DECLE   $0002, $0126, $0242, $0161, $03E9, $0219, $016C, $0300
    DECLE   $0013, $0045, $0124, $0005, $024C, $005C, $0182, $03C2
    DECLE   $0001
_SH.end:  ; 25 decles
;; ------------------------------------------------------------------------ ;;
_SS:
    DECLE   _SS.end - _SS - 1
    DECLE   $0218, $01CA, $0001, $0128, $001C, $0149, $01C6, $0000
_SS.end:  ; 8 decles
;; ------------------------------------------------------------------------ ;;
_TH:
    DECLE   _TH.end - _TH - 1
    DECLE   $0019, $0349, $0000, $00C6, $0212, $01D8, $01CA, $0000
_TH.end:  ; 8 decles
;; ------------------------------------------------------------------------ ;;
_TT1:
    DECLE   _TT1.end - _TT1 - 1
    DECLE   $00F6, $0046, $0142, $0100, $0042, $0088, $027E, $02EF
    DECLE   $01A4, $0200, $0049, $0290, $00FC, $00E8, $0000
_TT1.end:  ; 15 decles
;; ------------------------------------------------------------------------ ;;
_TT2:
    DECLE   _TT2.end - _TT2 - 1
    DECLE   $00F5, $00C6, $01D2, $0100, $0335, $00E9, $0042, $027A
    DECLE   $02A4, $0000, $0062, $01D1, $014C, $03EA, $02EC, $01E0
    DECLE   $0007, $03A7, $0000
_TT2.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_UH:
    DECLE   _UH.end - _UH - 1
    DECLE   $0018, $034E, $016E, $01FF, $0349, $00D2, $003C, $030C
    DECLE   $008B, $0005, $0000
_UH.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_UW1:
    DECLE   _UW1.end - _UW1 - 1
    DECLE   $0318, $014C, $016F, $029E, $03BD, $03BD, $0271, $0212
    DECLE   $0325, $0291, $016A, $027B, $014A, $03B4, $0133, $0001
_UW1.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_UW2:
    DECLE   _UW2.end - _UW2 - 1
    DECLE   $0018, $034E, $016E, $02F6, $0107, $02C2, $006D, $0090
    DECLE   $03AC, $01A4, $01DC, $03AB, $0128, $0076, $03E6, $0119
    DECLE   $014F, $03A6, $03A5, $0020, $0090, $0001, $02EE, $00BB
    DECLE   $0000
_UW2.end:  ; 25 decles
;; ------------------------------------------------------------------------ ;;
_VV:
    DECLE   _VV.end - _VV - 1
    DECLE   $0218, $030D, $016C, $010B, $010B, $0095, $034F, $03E4
    DECLE   $0108, $01B5, $01BE, $028B, $0160, $00AA, $03E4, $0106
    DECLE   $00EB, $02DE, $014C, $016E, $00F6, $0107, $00D2, $00CD
    DECLE   $0296, $00E4, $0006, $0000
_VV.end:  ; 28 decles
;; ------------------------------------------------------------------------ ;;
_WH:
    DECLE   _WH.end - _WH - 1
    DECLE   $0218, $00C9, $0000, $0084, $038E, $0147, $03A4, $0195
    DECLE   $0000, $012E, $0118, $0150, $02D1, $0232, $01B7, $03F1
    DECLE   $0237, $01C8, $03B1, $0227, $01AE, $0254, $0329, $032D
    DECLE   $01BF, $0169, $019A, $0307, $0181, $028D, $0000
_WH.end:  ; 31 decles
;; ------------------------------------------------------------------------ ;;
_WW:
    DECLE   _WW.end - _WW - 1
    DECLE   $0118, $034D, $016C, $00FA, $02C7, $0072, $03CC, $0109
    DECLE   $000B, $01AD, $019E, $016B, $0130, $0278, $01F8, $0314
    DECLE   $017E, $029E, $014D, $016D, $0205, $0147, $02E2, $001A
    DECLE   $010A, $026E, $0004, $0000
_WW.end:  ; 28 decles
;; ------------------------------------------------------------------------ ;;
_XR2:
    DECLE   _XR2.end - _XR2 - 1
    DECLE   $0318, $034C, $016E, $02A6, $03BB, $002F, $0290, $008E
    DECLE   $004B, $0392, $01DA, $024B, $013A, $01DA, $012F, $00B5
    DECLE   $02E5, $0297, $02DC, $0372, $014B, $016D, $0377, $00E7
    DECLE   $0376, $038A, $01CE, $026B, $02FA, $01AA, $011E, $0071
    DECLE   $00D5, $0297, $02BC, $02EA, $01C7, $02D7, $0135, $0155
    DECLE   $01DD, $0007, $0000
_XR2.end:  ; 43 decles
;; ------------------------------------------------------------------------ ;;
_YR:
    DECLE   _YR.end - _YR - 1
    DECLE   $0318, $03CC, $016E, $0197, $00FD, $0130, $0270, $0094
    DECLE   $0328, $0291, $0168, $007E, $01CC, $02F5, $0125, $02B5
    DECLE   $00F4, $0298, $01DA, $03F6, $0153, $0126, $03B9, $00AB
    DECLE   $0293, $03DB, $0175, $01B9, $0001
_YR.end:  ; 29 decles
;; ------------------------------------------------------------------------ ;;
_YY1:
    DECLE   _YY1.end - _YY1 - 1
    DECLE   $0318, $01CC, $016E, $0015, $00CB, $0263, $0320, $0078
    DECLE   $01CE, $0094, $001F, $0040, $0320, $03BF, $0230, $00A7
    DECLE   $000F, $01FE, $03FC, $01E2, $00D0, $0089, $000F, $0248
    DECLE   $032B, $03FD, $01CF, $0001, $0000
_YY1.end:  ; 29 decles
;; ------------------------------------------------------------------------ ;;
_YY2:
    DECLE   _YY2.end - _YY2 - 1
    DECLE   $0318, $01CC, $016E, $0015, $00CB, $0263, $0320, $0078
    DECLE   $01CE, $0094, $001F, $0040, $0320, $03BF, $0230, $00A7
    DECLE   $000F, $01FE, $03FC, $01E2, $00D0, $0089, $000F, $0248
    DECLE   $032B, $03FD, $01CF, $0199, $01EE, $008B, $0161, $0232
    DECLE   $0004, $0318, $01A7, $0198, $0124, $03E0, $0001, $0001
    DECLE   $030F, $0027, $0000
_YY2.end:  ; 43 decles
;; ------------------------------------------------------------------------ ;;
_ZH:
    DECLE   _ZH.end - _ZH - 1
    DECLE   $0310, $014D, $016E, $00C3, $03B9, $01BF, $0241, $0012
    DECLE   $0163, $00E1, $0000, $0080, $0084, $023F, $003F, $0000
_ZH.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_ZZ:
    DECLE   _ZZ.end - _ZZ - 1
    DECLE   $0218, $010D, $016F, $0225, $0351, $00B5, $02A0, $02EE
    DECLE   $00E9, $014D, $002C, $0360, $0008, $00EC, $004C, $0342
    DECLE   $03D4, $0156, $0052, $0131, $0008, $03B0, $01BE, $0172
    DECLE   $0000
_ZZ.end:  ; 25 decles

;;==========================================================================;;
;;									  ;;
;;  Copyright information:						  ;;
;;									  ;;
;;  The above allophone data was extracted from the SP0256-AL2 ROM image.   ;;
;;  The SP0256-AL2 allophones are NOT in the public domain, nor are they    ;;
;;  placed under the GNU General Public License.  This program is	   ;;
;;  distributed in the hope that it will be useful, but WITHOUT ANY	 ;;
;;  WARRANTY; without even the implied warranty of MERCHANTABILITY or       ;;
;;  FITNESS FOR A PARTICULAR PURPOSE.				       ;;
;;									  ;;
;;  Microchip, Inc. retains the copyright to the data and algorithms	;;
;;  contained in the SP0256-AL2.  This speech data is distributed with      ;;
;;  explicit permission from Microchip, Inc.  All such redistributions      ;;
;;  must retain this notice of copyright.				   ;;
;;									  ;;
;;  No copyright claims are made on this data by the author(s) of SDK1600.  ;;
;;  Please see http://spatula-city.org/~im14u2c/sp0256-al2/ for details.    ;;
;;									  ;;
;;==========================================================================;;

;* ======================================================================== *;
;*  These routines are placed into the public domain by their author.  All  *;
;*  copyright rights are hereby relinquished on the routines and data in    *;
;*  this file.  -- Joseph Zbiciak, 2008				     *;
;* ======================================================================== *;

;; ======================================================================== ;;
;;  INTELLIVOICE DRIVER ROUTINES					    ;;
;;  Written in 2002 by Joe Zbiciak <intvnut AT gmail.com>		   ;;
;;  http://spatula-city.org/~im14u2c/intv/				  ;;
;; ======================================================================== ;;

;; ======================================================================== ;;
;;  GLOBAL VARIABLES USED BY THESE ROUTINES				 ;;
;;									  ;;
;;  Note that some of these routines may use one or more global variables.  ;;
;;  If you use these routines, you will need to allocate the appropriate    ;;
;;  space in either 16-bit or 8-bit memory as appropriate.  Each global     ;;
;;  variable is listed with the routines which use it and the required      ;;
;;  memory width.							   ;;
;;									  ;;
;;  Example declarations for these routines are shown below, commented out. ;;
;;  You should uncomment these and add them to your program to make use of  ;;
;;  the routine that needs them.  Make sure to assign these variables to    ;;
;;  locations that aren't used for anything else.			   ;;
;; ======================================================================== ;;

			; Used by       Req'd Width     Description
			;-----------------------------------------------------
;IV.QH      EQU $110    ; IV_xxx	8-bit	   Voice queue head
;IV.QT      EQU $111    ; IV_xxx	8-bit	   Voice queue tail
;IV.Q       EQU $112    ; IV_xxx	8-bit	   Voice queue  (8 bytes)
;IV.FLEN    EQU $11A    ; IV_xxx	8-bit	   Length of FIFO data
;IV.FPTR    EQU $320    ; IV_xxx	16-bit	  Current FIFO ptr.
;IV.PPTR    EQU $321    ; IV_xxx	16-bit	  Current Phrase ptr.

;; ======================================================================== ;;
;;  MEMORY USAGE							    ;;
;;									  ;;
;;  These routines implement a queue of "pending phrases" that will be      ;;
;;  played by the Intellivoice.  The user calls IV_PLAY to enqueue a	;;
;;  phrase number.  Phrase numbers indicate either a RESROM sample or       ;;
;;  a compiled in phrase to be spoken.				      ;;
;;									  ;;
;;  The user must compose an "IV_PHRASE_TBL", which is composed of	  ;;
;;  pointers to phrases to be spoken.  Phrases are strings of pointers      ;;
;;  and RESROM triggers, terminated by a NUL.			       ;;
;;									  ;;
;;  Phrase numbers 1 through 42 are RESROM samples.  Phrase numbers	 ;;
;;  43 through 255 index into the IV_PHRASE_TBL.			    ;;
;;									  ;;
;;  SPECIAL NOTES							   ;;
;;									  ;;
;;  Bit 7 of IV.QH and IV.QT is used to denote whether the Intellivoice     ;;
;;  is present.  If Intellivoice is present, this bit is clear.	     ;;
;;									  ;;
;;  Bit 6 of IV.QT is used to denote that we still need to do an ALD $00    ;;
;;  for FIFO'd voice data.						  ;;
;; ======================================================================== ;;
	    

;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_INIT     Initialize the Intellivoice			     ;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_INIT						      ;;
;;      R5      Return address					      ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;      R0      0 if Intellivoice found, -1 if not.			 ;;
;;									  ;;
;;  DESCRIPTION							     ;;
;;      Resets Intellivoice, determines if it is actually there, and	;;
;;      then initializes the IV structure.				  ;;
;; ------------------------------------------------------------------------ ;;
;;		   Copyright (c) 2002, Joseph Zbiciak		     ;;
;; ======================================================================== ;;

IV_INIT     PROC
	    MVII    #$0400, R0	  ;
	    MVO     R0,     $0081       ; Reset the Intellivoice

	    MVI     $0081,  R0	  ; \
	    RLC     R0,     2	   ;  |-- See if we detect Intellivoice
	    BOV     @@no_ivoice	 ; /    once we've reset it.

	    CLRR    R0		  ; 
	    MVO     R0,     IV.FPTR     ; No data for FIFO
	    MVO     R0,     IV.PPTR     ; No phrase being spoken
	    MVO     R0,     IV.QH       ; Clear our queue
	    MVO     R0,     IV.QT       ; Clear our queue
	    JR      R5		  ; Done!

@@no_ivoice:
	    CLRR    R0
	    MVO     R0,     IV.FPTR     ; No data for FIFO
	    MVO     R0,     IV.PPTR     ; No phrase being spoken
	    DECR    R0
	    MVO     R0,     IV.QH       ; Set queue to -1 ("No Intellivoice")
	    MVO     R0,     IV.QT       ; Set queue to -1 ("No Intellivoice")
;	    JR      R5		 ; Done!
	    B       _wait	       ; Special for IntyBASIC!
	    ENDP

;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_ISR      Interrupt service routine to feed Intellivoice	  ;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_ISR						       ;;
;;      R5      Return address					      ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;      R0, R1, R4 trashed.						 ;;
;;									  ;;
;;  NOTES								   ;;
;;      Call this from your main interrupt service routine.		 ;;
;; ------------------------------------------------------------------------ ;;
;;		   Copyright (c) 2002, Joseph Zbiciak		     ;;
;; ======================================================================== ;;
IV_ISR      PROC
	    ;; ------------------------------------------------------------ ;;
	    ;;  Check for Intellivoice.  Leave if none present.	     ;;
	    ;; ------------------------------------------------------------ ;;
	    MVI     IV.QT,  R1	  ; Get queue tail
	    SWAP    R1,     2
	    BPL     @@ok		; Bit 7 set? If yes: No Intellivoice
@@ald_busy:
@@leave     JR      R5		  ; Exit if no Intellivoice.

     
	    ;; ------------------------------------------------------------ ;;
	    ;;  Check to see if we pump samples into the FIFO.
	    ;; ------------------------------------------------------------ ;;
@@ok:       MVI     IV.FPTR, R4	 ; Get FIFO data pointer
	    TSTR    R4		  ; is it zero?
	    BEQ     @@no_fifodata       ; Yes:  No data for FIFO.
@@fifo_fill:
	    MVI     $0081,  R0	  ; Read speech FIFO ready bit
	    SLLC    R0,     1	   ; 
	    BC      @@fifo_busy     

	    MVI@    R4,     R0	  ; Get next word
	    MVO     R0,     $0081       ; write it to the FIFO

	    MVI     IV.FLEN, R0	 ;\
	    DECR    R0		  ; |-- Decrement our FIFO'd data length
	    MVO     R0,     IV.FLEN     ;/
	    BEQ     @@last_fifo	 ; If zero, we're done w/ FIFO
	    MVO     R4,     IV.FPTR     ; Otherwise, save new pointer
	    B       @@fifo_fill	 ; ...and keep trying to load FIFO

@@last_fifo MVO     R0,     IV.FPTR     ; done with FIFO loading.
					; fall into ALD processing.


	    ;; ------------------------------------------------------------ ;;
	    ;;  Try to do an Address Load.  We do this in two settings:     ;;
	    ;;   -- We have no FIFO data to load.			   ;;
	    ;;   -- We've loaded as much FIFO data as we can, but we	;;
	    ;;      might have an address load command to send for it.      ;;
	    ;; ------------------------------------------------------------ ;;
@@fifo_busy:
@@no_fifodata:
	    MVI     $0080,  R0	  ; Read LRQ bit from ALD register
	    SLLC    R0,     1
	    BNC     @@ald_busy	  ; LRQ is low, meaning we can't ALD.
					; So, leave.

	    ;; ------------------------------------------------------------ ;;
	    ;;  We can do an address load (ALD) on the SP0256.  Give FIFO   ;;
	    ;;  driven ALDs priority, since we already started the FIFO     ;;
	    ;;  load.  The "need ALD" bit is stored in bit 6 of IV.QT.      ;;
	    ;; ------------------------------------------------------------ ;;
	    ANDI    #$40,   R1	  ; Is "Need FIFO ALD" bit set?
	    BEQ     @@no_fifo_ald
	    XOR     IV.QT,  R1	  ;\__ Clear the "Need FIFO ALD" bit.
	    MVO     R1,     IV.QT       ;/
	    CLRR    R1
	    MVO     R1,     $80	 ; Load a 0 into ALD (trigger FIFO rd.)
	    JR      R5		  ; done!

	    ;; ------------------------------------------------------------ ;;
	    ;;  We don't need to ALD on behalf of the FIFO.  So, we grab    ;;
	    ;;  the next thing off our phrase list.			 ;;
	    ;; ------------------------------------------------------------ ;;
@@no_fifo_ald:
	    MVI     IV.PPTR, R4	 ; Get phrase pointer.
	    TSTR    R4		  ; Is it zero?
	    BEQ     @@next_phrase       ; Yes:  Get next phrase from queue.

	    MVI@    R4,     R0
	    TSTR    R0		  ; Is it end of phrase?
	    BNEQ    @@process_phrase    ; !=0:  Go do it.

	    MVO     R0,     IV.PPTR     ; 
@@next_phrase:
	    MVI     IV.QT,  R1	  ; reload queue tail (was trashed above)
	    MOVR    R1,     R0	  ; copy QT to R0 so we can increment it
	    ANDI    #$7,    R1	  ; Mask away flags in queue head
	    CMP     IV.QH,  R1	  ; Is it same as queue tail?
	    BEQ     @@leave	     ; Yes:  No more speech for now.

	    INCR    R0
	    ANDI    #$F7,   R0	  ; mask away the possible 'carry'
	    MVO     R0,     IV.QT       ; save updated queue tail

	    ADDI    #IV.Q,  R1	  ; Index into queue
	    MVI@    R1,     R4	  ; get next value from queue
	    CMPI    #43,    R4	  ; Is it a RESROM or Phrase?
	    BNC     @@play_resrom_r4
@@new_phrase:
;	    ADDI    #IV_PHRASE_TBL - 43, R4 ; Index into phrase table
;	    MVI@    R4,     R4	  ; Read from phrase table
	    MVO     R4,     IV.PPTR
	    JR      R5		  ; we'll get to this phrase next time.

@@play_resrom_r4:
	    MVO     R4,     $0080       ; Just ALD it
	    JR      R5		  ; and leave.

	    ;; ------------------------------------------------------------ ;;
	    ;;  We're in the middle of a phrase, so continue interpreting.  ;;
	    ;; ------------------------------------------------------------ ;;
@@process_phrase:
	    
	    MVO     R4,     IV.PPTR     ; save new phrase pointer
	    CMPI    #43,    R0	  ; Is it a RESROM cue?
	    BC      @@play_fifo	 ; Just ALD it and leave.
@@play_resrom_r0
	    MVO     R0,     $0080       ; Just ALD it
	    JR      R5		  ; and leave.
@@play_fifo:
	    MVI     IV.FPTR,R1	  ; Make sure not to stomp existing FIFO
	    TSTR    R1		  ; data.
	    BEQ     @@new_fifo_ok
	    DECR    R4		  ; Oops, FIFO data still playing,
	    MVO     R4,     IV.PPTR     ; so rewind.
	    JR      R5		  ; and leave.

@@new_fifo_ok:
	    MOVR    R0,     R4	  ;
	    MVI@    R4,     R0	  ; Get chunk length
	    MVO     R0,     IV.FLEN     ; Init FIFO chunk length
	    MVO     R4,     IV.FPTR     ; Init FIFO pointer
	    MVI     IV.QT,  R0	  ;\
	    XORI    #$40,   R0	  ; |- Set "Need ALD" bit in QT
	    MVO     R0,     IV.QT       ;/

  IF 1      ; debug code		;\
	    ANDI    #$40,   R0	  ; |   Debug code:  We should only
	    BNEQ    @@qtok	      ; |-- be here if "Need FIFO ALD" 
	    HLT     ;BUG!!	      ; |   was already clear.	 
@@qtok				  ;/    
  ENDI
	    JR      R5		  ; leave.

	    ENDP


;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_PLAY     Play a voice sample sequence.			   ;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_PLAY						      ;;
;;      R5      Invocation record, followed by return address.	      ;;
;;		  1 DECLE    Phrase number to play.		       ;;
;;									  ;;
;;  INPUTS for IV_PLAY.1						    ;;
;;      R0      Address of phrase to play.				  ;;
;;      R5      Return address					      ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;      R0, R1  trashed						     ;;
;;      Z==0    if item not successfully queued.			    ;;
;;      Z==1    if successfully queued.				     ;;
;;									  ;;
;;  NOTES								   ;;
;;      This code will drop phrases if the queue is full.		   ;;
;;      Phrase numbers 1..42 are RESROM samples.  43..255 will index	;;
;;      into the user-supplied IV_PHRASE_TBL.  43 will refer to the	 ;;
;;      first entry, 44 to the second, and so on.  Phrase 0 is undefined.   ;;
;;									  ;;
;; ------------------------------------------------------------------------ ;;
;;		   Copyright (c) 2002, Joseph Zbiciak		     ;;
;; ======================================================================== ;;
IV_PLAY     PROC
	    MVI@    R5,     R0

@@1:	; alternate entry point
	    MVI     IV.QT,  R1	  ; Get queue tail
	    SWAP    R1,     2	   ;\___ Leave if "no Intellivoice"
	    BMI     @@leave	     ;/    bit it set.
@@ok:       
	    DECR    R1		  ;\
	    ANDI    #$7,    R1	  ; |-- See if we still have room
	    CMP     IV.QH,  R1	  ;/
	    BEQ     @@leave	     ; Leave if we're full

@@2:	MVI     IV.QH,  R1	  ; Get our queue head pointer
	    PSHR    R1		  ;\
	    INCR    R1		  ; |
	    ANDI    #$F7,   R1	  ; |-- Increment it, removing
	    MVO     R1,     IV.QH       ; |   carry but preserving flags.
	    PULR    R1		  ;/

	    ADDI    #IV.Q,  R1	  ;\__ Store phrase to queue
	    MVO@    R0,     R1	  ;/

@@leave:    JR      R5		  ; Leave.
	    ENDP

;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_PLAYW    Play a voice sample sequence.  Wait for queue room.     ;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_PLAY						      ;;
;;      R5      Invocation record, followed by return address.	      ;;
;;		  1 DECLE    Phrase number to play.		       ;;
;;									  ;;
;;  INPUTS for IV_PLAY.1						    ;;
;;      R0      Address of phrase to play.				  ;;
;;      R5      Return address					      ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;      R0, R1  trashed						     ;;
;;									  ;;
;;  NOTES								   ;;
;;      This code will wait for a queue slot to open if queue is full.      ;;
;;      Phrase numbers 1..42 are RESROM samples.  43..255 will index	;;
;;      into the user-supplied IV_PHRASE_TBL.  43 will refer to the	 ;;
;;      first entry, 44 to the second, and so on.  Phrase 0 is undefined.   ;;
;;									  ;;
;; ------------------------------------------------------------------------ ;;
;;		   Copyright (c) 2002, Joseph Zbiciak		     ;;
;; ======================================================================== ;;
IV_PLAYW    PROC
	    MVI@    R5,     R0

@@1:	; alternate entry point
	    MVI     IV.QT,  R1	  ; Get queue tail
	    SWAP    R1,     2	   ;\___ Leave if "no Intellivoice"
	    BMI     IV_PLAY.leave       ;/    bit it set.
@@ok:       
	    DECR    R1		  ;\
	    ANDI    #$7,    R1	  ; |-- See if we still have room
	    CMP     IV.QH,  R1	  ;/
	    BEQ     @@1		 ; wait for room
	    B       IV_PLAY.2

	    ENDP

;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_HUSH     Flush the speech queue, and hush the Intellivoice.      ;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      02-Feb-2018 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_HUSH						      ;;
;;      None.							       ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;      R0 trashed.							 ;;
;;									  ;;
;;  NOTES								   ;;
;;      Returns via IV_WAIT.						;;
;;									  ;;
;; ======================================================================== ;;
IV_HUSH:    PROC
	    MVI     IV.QH,  R0
	    SWAP    R0,     2
	    BMI     IV_WAIT.leave

	    DIS
	    ;; We can't stop a phrase segment that's being FIFOed down.
	    ;; We need to remember if we've committed to pushing ALD.
	    ;; We _can_ stop new phrase segments from going down, and _can_
	    ;; stop new phrases from being started.

	    ;; Set head pointer to indicate we've inserted one item.
	    MVI     IV.QH,  R0  ; Re-read, as an interrupt may have occurred
	    ANDI    #$F0,   R0
	    INCR    R0
	    MVO     R0,     IV.QH

	    ;; Reset tail pointer, keeping "need ALD" bit and other flags.
	    MVI     IV.QT,  R0
	    ANDI    #$F0,   R0
	    MVO     R0,     IV.QT

	    ;; Reset the phrase pointer, to stop a long phrase.
	    CLRR    R0
	    MVO     R0,     IV.PPTR

	    ;; Queue a PA1 in the queue.  Since we're can't guarantee the user
	    ;; has included resrom.asm, let's just use the raw number (5).
	    MVII    #5,     R0
	    MVO     R0,     IV.Q

	    ;; Re-enable interrupts and wait for Intellivoice to shut up.
	    ;;
	    ;; We can't just jump to IV_WAIT.q_loop, as we need to reload
	    ;; IV.QH into R0, and I'm really committed to only using R0.
;	   JE      IV_WAIT
	    EIS
	    ; fallthrough into IV_WAIT
	    ENDP

;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_WAIT     Wait for voice queue to empty.			  ;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_WAIT						      ;;
;;      R5      Return address					      ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;      R0      trashed.						    ;;
;;									  ;;
;;  NOTES								   ;;
;;      This waits until the Intellivoice is nearly completely quiescent.   ;;
;;      Some voice data may still be spoken from the last triggered	 ;;
;;      phrase.  To truly wait for *that* to be spoken, speak a 'pause'     ;;
;;      (eg. RESROM.pa1) and then call IV_WAIT.			     ;;
;; ------------------------------------------------------------------------ ;;
;;		   Copyright (c) 2002, Joseph Zbiciak		     ;;
;; ======================================================================== ;;
IV_WAIT     PROC
	    MVI     IV.QH,  R0
	    CMPI    #$80, R0	    ; test bit 7, leave if set.
	    BC      @@leave

	    ; Wait for queue to drain.
@@q_loop:   CMP     IV.QT,  R0
	    BNEQ    @@q_loop

	    ; Wait for FIFO and LRQ to say ready.
@@s_loop:   MVI     $81,    R0	  ; Read FIFO status.  0 == ready.
	    COMR    R0
	    AND     $80,    R0	  ; Merge w/ ALD status.  1 == ready
	    TSTR    R0
	    BPL     @@s_loop	    ; if bit 15 == 0, not ready.
	    
@@leave:    JR      R5
	    ENDP

;; ======================================================================== ;;
;;  End of File:  ivoice.asm						;;
;; ======================================================================== ;;

;* ======================================================================== *;
;*  These routines are placed into the public domain by their author.  All  *;
;*  copyright rights are hereby relinquished on the routines and data in    *;
;*  this file.  -- Joseph Zbiciak, 2008				     *;
;* ======================================================================== *;

;; ======================================================================== ;;
;;  NAME								    ;;
;;      IV_SAYNUM16 Say a 16-bit unsigned number using RESROM digits	;;
;;									  ;;
;;  AUTHOR								  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>			       ;;
;;									  ;;
;;  REVISION HISTORY							;;
;;      16-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;									  ;;
;;  INPUTS for IV_SAYNUM16						  ;;
;;      R0      Number to "speak"					   ;;
;;      R5      Return address					      ;;
;;									  ;;
;;  OUTPUTS								 ;;
;;									  ;;
;;  DESCRIPTION							     ;;
;;      "Says" a 16-bit number using IV_PLAYW to queue up the phrase.       ;;
;;      Because the number may be built from several segments, it could     ;;
;;      easily eat up the queue.  I believe the longest number will take    ;;
;;      7 queue entries -- that is, fill the queue.  Thus, this code	;;
;;      could block, waiting for slots in the queue.			;;
;; ======================================================================== ;;

IV_SAYNUM16 PROC
	    PSHR    R5

	    TSTR    R0
	    BEQ     @@zero	  ; Special case:  Just say "zero"

	    ;; ------------------------------------------------------------ ;;
	    ;;  First, try to pull off 'thousands'.  We call ourselves      ;;
	    ;;  recursively to play the the number of thousands.	    ;;
	    ;; ------------------------------------------------------------ ;;
	    CLRR    R1
@@thloop:   INCR    R1
	    SUBI    #1000,  R0
	    BC      @@thloop

	    ADDI    #1000,  R0
	    PSHR    R0
	    DECR    R1
	    BEQ     @@no_thousand

	    CALL    IV_SAYNUM16.recurse

	    CALL    IV_PLAYW
	    DECLE   36  ; THOUSAND
	    
@@no_thousand
	    PULR    R1

	    ;; ------------------------------------------------------------ ;;
	    ;;  Now try to play hundreds.				   ;;
	    ;; ------------------------------------------------------------ ;;
	    MVII    #7-1, R0    ; ZERO
	    CMPI    #100,   R1
	    BNC     @@no_hundred

@@hloop:    INCR    R0
	    SUBI    #100,   R1
	    BC      @@hloop
	    ADDI    #100,   R1

	    PSHR    R1

	    CALL    IV_PLAYW.1

	    CALL    IV_PLAYW
	    DECLE   35  ; HUNDRED

	    PULR    R1
	    B       @@notrecurse    ; skip "PSHR R5"
@@recurse:  PSHR    R5	      ; recursive entry point for 'thousand'

@@no_hundred:
@@notrecurse:
	    MOVR    R1,     R0
	    BEQ     @@leave

	    SUBI    #20,    R1
	    BNC     @@teens

	    MVII    #27-1, R0   ; TWENTY
@@tyloop    INCR    R0
	    SUBI    #10,    R1
	    BC      @@tyloop
	    ADDI    #10,    R1

	    PSHR    R1
	    CALL    IV_PLAYW.1

	    PULR    R0
	    TSTR    R0
	    BEQ     @@leave

@@teens:
@@zero:     ADDI    #7, R0  ; ZERO

	    CALL    IV_PLAYW.1

@@leave     PULR    PC
	    ENDP

;; ======================================================================== ;;
;;  End of File:  saynum16.asm					      ;;
;; ======================================================================== ;;

IV_INIT_and_wait:     EQU IV_INIT

    ELSE

IV_INIT_and_wait:     EQU _wait	; No voice init; just WAIT.

    ENDI

	IF intybasic_flash

;; ======================================================================== ;;
;;  JLP "Save Game" support						 ;;
;; ======================================================================== ;;
JF.first    EQU     $8023
JF.last     EQU     $8024
JF.addr     EQU     $8025
JF.row      EQU     $8026
		   
JF.wrcmd    EQU     $802D
JF.rdcmd    EQU     $802E
JF.ercmd    EQU     $802F
JF.wrkey    EQU     $C0DE
JF.rdkey    EQU     $DEC0
JF.erkey    EQU     $BEEF

JF.write:   DECLE   JF.wrcmd,   JF.wrkey    ; Copy JLP RAM to flash row  
JF.read:    DECLE   JF.rdcmd,   JF.rdkey    ; Copy flash row to JLP RAM  
JF.erase:   DECLE   JF.ercmd,   JF.erkey    ; Erase flash sector 

;; ======================================================================== ;;
;;  JF.INIT	 Copy JLP save-game support routine to System RAM	;;
;; ======================================================================== ;;
JF.INIT     PROC
	    PSHR    R5	    
	    MVII    #@@__code,  R5
	    MVII    #JF.SYSRAM, R4
	    REPEAT  5       
	    MVI@    R5,	 R0      ; \_ Copy code fragment to System RAM
	    MVO@    R0,	 R4      ; /
	    ENDR
	    PULR    PC

	    ;; === start of code that will run from RAM
@@__code:   MVO@    R0,	 R1      ; JF.SYSRAM + 0: initiate command
	    ADD@    R1,	 PC      ; JF.SYSRAM + 1: Wait for JLP to return
	    JR      R5		  ; JF.SYSRAM + 2:
	    MVO@    R2,	 R2      ; JF.SYSRAM + 3: \__ simple ISR
	    JR      R5		  ; JF.SYSRAM + 4: /
	    ;; === end of code that will run from RAM
	    ENDP

;; ======================================================================== ;;
;;  JF.CMD	  Issue a JLP Flash command			       ;;
;;									  ;;
;;  INPUT								   ;;
;;      R0  Slot number to operate on				       ;;
;;      R1  Address to copy to/from in JLP RAM			      ;;
;;      @R5 Command to invoke:					      ;;
;;									  ;;
;;	      JF.write -- Copy JLP RAM to Flash			   ;;
;;	      JF.read  -- Copy Flash to JLP RAM			   ;;
;;	      JF.erase -- Erase flash sector			      ;;
;;									  ;;
;;  OUTPUT								  ;;
;;      R0 - R4 not modified.  (Saved and restored across call)	     ;;
;;      JLP command executed						;;
;;									  ;;
;;  NOTES								   ;;
;;      This code requires two short routines in the console's System RAM.  ;;
;;      It also requires that the system stack reside in System RAM.	;;
;;      Because an interrupt may occur during the code's execution, there   ;;
;;      must be sufficient stack space to service the interrupt (8 words).  ;;
;;									  ;;
;;      The code also relies on the fact that the EXEC ISR dispatch does    ;;
;;      not modify R2.  This allows us to initialize R2 for the ISR ahead   ;;
;;      of time, rather than in the ISR.				    ;;
;; ======================================================================== ;;
JF.CMD      PROC

	    MVO     R4,	 JF.SV.R4    ; \
	    MVII    #JF.SV.R0,  R4	  ;  |
	    MVO@    R0,	 R4	  ;  |- Save registers, but not on
	    MVO@    R1,	 R4	  ;  |  the stack.  (limit stack use)
	    MVO@    R2,	 R4	  ; /

	    MVI@    R5,	 R4	  ; Get command to invoke

	    MVO     R5,	 JF.SV.R5    ; save return address

	    DIS
	    MVO     R1,	 JF.addr     ; \_ Save SG arguments in JLP
	    MVO     R0,	 JF.row      ; /
					  
	    MVI@    R4,	 R1	  ; Get command address
	    MVI@    R4,	 R0	  ; Get unlock word
					  
	    MVII    #$100,      R4	  ; \
	    SDBD			    ;  |_ Save old ISR in save area
	    MVI@    R4,	 R2	  ;  |
	    MVO     R2,	 JF.SV.ISR   ; /
					  
	    MVII    #JF.SYSRAM + 3, R2      ; \
	    MVO     R2,	 $100	;  |_ Set up new ISR in RAM
	    SWAP    R2		      ;  |
	    MVO     R2,	 $101	; / 
					  
	    MVII    #$20,       R2	  ; Address of STIC handshake
	    JSRE    R5,  JF.SYSRAM	  ; Invoke the command
					  
	    MVI     JF.SV.ISR,  R2	  ; \
	    MVO     R2,	 $100	;  |_ Restore old ISR 
	    SWAP    R2		      ;  |
	    MVO     R2,	 $101	; /
					  
	    MVII    #JF.SV.R0,  R5	  ; \
	    MVI@    R5,	 R0	  ;  |
	    MVI@    R5,	 R1	  ;  |- Restore registers
	    MVI@    R5,	 R2	  ;  |
	    MVI@    R5,	 R4	  ; /
	    MVI@    R5,	 PC	  ; Return

	    ENDP


	ENDI

	IF intybasic_fastmult

; Quarter Square Multiplication
; Assembly code by Joe Zbiciak, 2015
; Released to public domain.

QSQR8_TBL:  PROC
	    DECLE   $3F80, $3F01, $3E82, $3E04, $3D86, $3D09, $3C8C, $3C10
	    DECLE   $3B94, $3B19, $3A9E, $3A24, $39AA, $3931, $38B8, $3840
	    DECLE   $37C8, $3751, $36DA, $3664, $35EE, $3579, $3504, $3490
	    DECLE   $341C, $33A9, $3336, $32C4, $3252, $31E1, $3170, $3100
	    DECLE   $3090, $3021, $2FB2, $2F44, $2ED6, $2E69, $2DFC, $2D90
	    DECLE   $2D24, $2CB9, $2C4E, $2BE4, $2B7A, $2B11, $2AA8, $2A40
	    DECLE   $29D8, $2971, $290A, $28A4, $283E, $27D9, $2774, $2710
	    DECLE   $26AC, $2649, $25E6, $2584, $2522, $24C1, $2460, $2400
	    DECLE   $23A0, $2341, $22E2, $2284, $2226, $21C9, $216C, $2110
	    DECLE   $20B4, $2059, $1FFE, $1FA4, $1F4A, $1EF1, $1E98, $1E40
	    DECLE   $1DE8, $1D91, $1D3A, $1CE4, $1C8E, $1C39, $1BE4, $1B90
	    DECLE   $1B3C, $1AE9, $1A96, $1A44, $19F2, $19A1, $1950, $1900
	    DECLE   $18B0, $1861, $1812, $17C4, $1776, $1729, $16DC, $1690
	    DECLE   $1644, $15F9, $15AE, $1564, $151A, $14D1, $1488, $1440
	    DECLE   $13F8, $13B1, $136A, $1324, $12DE, $1299, $1254, $1210
	    DECLE   $11CC, $1189, $1146, $1104, $10C2, $1081, $1040, $1000
	    DECLE   $0FC0, $0F81, $0F42, $0F04, $0EC6, $0E89, $0E4C, $0E10
	    DECLE   $0DD4, $0D99, $0D5E, $0D24, $0CEA, $0CB1, $0C78, $0C40
	    DECLE   $0C08, $0BD1, $0B9A, $0B64, $0B2E, $0AF9, $0AC4, $0A90
	    DECLE   $0A5C, $0A29, $09F6, $09C4, $0992, $0961, $0930, $0900
	    DECLE   $08D0, $08A1, $0872, $0844, $0816, $07E9, $07BC, $0790
	    DECLE   $0764, $0739, $070E, $06E4, $06BA, $0691, $0668, $0640
	    DECLE   $0618, $05F1, $05CA, $05A4, $057E, $0559, $0534, $0510
	    DECLE   $04EC, $04C9, $04A6, $0484, $0462, $0441, $0420, $0400
	    DECLE   $03E0, $03C1, $03A2, $0384, $0366, $0349, $032C, $0310
	    DECLE   $02F4, $02D9, $02BE, $02A4, $028A, $0271, $0258, $0240
	    DECLE   $0228, $0211, $01FA, $01E4, $01CE, $01B9, $01A4, $0190
	    DECLE   $017C, $0169, $0156, $0144, $0132, $0121, $0110, $0100
	    DECLE   $00F0, $00E1, $00D2, $00C4, $00B6, $00A9, $009C, $0090
	    DECLE   $0084, $0079, $006E, $0064, $005A, $0051, $0048, $0040
	    DECLE   $0038, $0031, $002A, $0024, $001E, $0019, $0014, $0010
	    DECLE   $000C, $0009, $0006, $0004, $0002, $0001, $0000
@@mid:
	    DECLE   $0000, $0000, $0001, $0002, $0004, $0006, $0009, $000C
	    DECLE   $0010, $0014, $0019, $001E, $0024, $002A, $0031, $0038
	    DECLE   $0040, $0048, $0051, $005A, $0064, $006E, $0079, $0084
	    DECLE   $0090, $009C, $00A9, $00B6, $00C4, $00D2, $00E1, $00F0
	    DECLE   $0100, $0110, $0121, $0132, $0144, $0156, $0169, $017C
	    DECLE   $0190, $01A4, $01B9, $01CE, $01E4, $01FA, $0211, $0228
	    DECLE   $0240, $0258, $0271, $028A, $02A4, $02BE, $02D9, $02F4
	    DECLE   $0310, $032C, $0349, $0366, $0384, $03A2, $03C1, $03E0
	    DECLE   $0400, $0420, $0441, $0462, $0484, $04A6, $04C9, $04EC
	    DECLE   $0510, $0534, $0559, $057E, $05A4, $05CA, $05F1, $0618
	    DECLE   $0640, $0668, $0691, $06BA, $06E4, $070E, $0739, $0764
	    DECLE   $0790, $07BC, $07E9, $0816, $0844, $0872, $08A1, $08D0
	    DECLE   $0900, $0930, $0961, $0992, $09C4, $09F6, $0A29, $0A5C
	    DECLE   $0A90, $0AC4, $0AF9, $0B2E, $0B64, $0B9A, $0BD1, $0C08
	    DECLE   $0C40, $0C78, $0CB1, $0CEA, $0D24, $0D5E, $0D99, $0DD4
	    DECLE   $0E10, $0E4C, $0E89, $0EC6, $0F04, $0F42, $0F81, $0FC0
	    DECLE   $1000, $1040, $1081, $10C2, $1104, $1146, $1189, $11CC
	    DECLE   $1210, $1254, $1299, $12DE, $1324, $136A, $13B1, $13F8
	    DECLE   $1440, $1488, $14D1, $151A, $1564, $15AE, $15F9, $1644
	    DECLE   $1690, $16DC, $1729, $1776, $17C4, $1812, $1861, $18B0
	    DECLE   $1900, $1950, $19A1, $19F2, $1A44, $1A96, $1AE9, $1B3C
	    DECLE   $1B90, $1BE4, $1C39, $1C8E, $1CE4, $1D3A, $1D91, $1DE8
	    DECLE   $1E40, $1E98, $1EF1, $1F4A, $1FA4, $1FFE, $2059, $20B4
	    DECLE   $2110, $216C, $21C9, $2226, $2284, $22E2, $2341, $23A0
	    DECLE   $2400, $2460, $24C1, $2522, $2584, $25E6, $2649, $26AC
	    DECLE   $2710, $2774, $27D9, $283E, $28A4, $290A, $2971, $29D8
	    DECLE   $2A40, $2AA8, $2B11, $2B7A, $2BE4, $2C4E, $2CB9, $2D24
	    DECLE   $2D90, $2DFC, $2E69, $2ED6, $2F44, $2FB2, $3021, $3090
	    DECLE   $3100, $3170, $31E1, $3252, $32C4, $3336, $33A9, $341C
	    DECLE   $3490, $3504, $3579, $35EE, $3664, $36DA, $3751, $37C8
	    DECLE   $3840, $38B8, $3931, $39AA, $3A24, $3A9E, $3B19, $3B94
	    DECLE   $3C10, $3C8C, $3D09, $3D86, $3E04, $3E82, $3F01, $3F80
	    DECLE   $4000, $4080, $4101, $4182, $4204, $4286, $4309, $438C
	    DECLE   $4410, $4494, $4519, $459E, $4624, $46AA, $4731, $47B8
	    DECLE   $4840, $48C8, $4951, $49DA, $4A64, $4AEE, $4B79, $4C04
	    DECLE   $4C90, $4D1C, $4DA9, $4E36, $4EC4, $4F52, $4FE1, $5070
	    DECLE   $5100, $5190, $5221, $52B2, $5344, $53D6, $5469, $54FC
	    DECLE   $5590, $5624, $56B9, $574E, $57E4, $587A, $5911, $59A8
	    DECLE   $5A40, $5AD8, $5B71, $5C0A, $5CA4, $5D3E, $5DD9, $5E74
	    DECLE   $5F10, $5FAC, $6049, $60E6, $6184, $6222, $62C1, $6360
	    DECLE   $6400, $64A0, $6541, $65E2, $6684, $6726, $67C9, $686C
	    DECLE   $6910, $69B4, $6A59, $6AFE, $6BA4, $6C4A, $6CF1, $6D98
	    DECLE   $6E40, $6EE8, $6F91, $703A, $70E4, $718E, $7239, $72E4
	    DECLE   $7390, $743C, $74E9, $7596, $7644, $76F2, $77A1, $7850
	    DECLE   $7900, $79B0, $7A61, $7B12, $7BC4, $7C76, $7D29, $7DDC
	    DECLE   $7E90, $7F44, $7FF9, $80AE, $8164, $821A, $82D1, $8388
	    DECLE   $8440, $84F8, $85B1, $866A, $8724, $87DE, $8899, $8954
	    DECLE   $8A10, $8ACC, $8B89, $8C46, $8D04, $8DC2, $8E81, $8F40
	    DECLE   $9000, $90C0, $9181, $9242, $9304, $93C6, $9489, $954C
	    DECLE   $9610, $96D4, $9799, $985E, $9924, $99EA, $9AB1, $9B78
	    DECLE   $9C40, $9D08, $9DD1, $9E9A, $9F64, $A02E, $A0F9, $A1C4
	    DECLE   $A290, $A35C, $A429, $A4F6, $A5C4, $A692, $A761, $A830
	    DECLE   $A900, $A9D0, $AAA1, $AB72, $AC44, $AD16, $ADE9, $AEBC
	    DECLE   $AF90, $B064, $B139, $B20E, $B2E4, $B3BA, $B491, $B568
	    DECLE   $B640, $B718, $B7F1, $B8CA, $B9A4, $BA7E, $BB59, $BC34
	    DECLE   $BD10, $BDEC, $BEC9, $BFA6, $C084, $C162, $C241, $C320
	    DECLE   $C400, $C4E0, $C5C1, $C6A2, $C784, $C866, $C949, $CA2C
	    DECLE   $CB10, $CBF4, $CCD9, $CDBE, $CEA4, $CF8A, $D071, $D158
	    DECLE   $D240, $D328, $D411, $D4FA, $D5E4, $D6CE, $D7B9, $D8A4
	    DECLE   $D990, $DA7C, $DB69, $DC56, $DD44, $DE32, $DF21, $E010
	    DECLE   $E100, $E1F0, $E2E1, $E3D2, $E4C4, $E5B6, $E6A9, $E79C
	    DECLE   $E890, $E984, $EA79, $EB6E, $EC64, $ED5A, $EE51, $EF48
	    DECLE   $F040, $F138, $F231, $F32A, $F424, $F51E, $F619, $F714
	    DECLE   $F810, $F90C, $FA09, $FB06, $FC04, $FD02, $FE01
	    ENDP

; R0 = R0 * R1, where R0 and R1 are unsigned 8-bit values
; Destroys R1, R4
qs_mpy8:    PROC
	    MOVR    R0,	     R4      ;   6
	    ADDI    #QSQR8_TBL.mid, R1      ;   8
	    ADDR    R1,	     R4      ;   6   a + b
	    SUBR    R0,	     R1      ;   6   a - b
@@ok:       MVI@    R4,	     R0      ;   8
	    SUB@    R1,	     R0      ;   8
	    JR      R5		      ;   7
					    ;----
					    ;  49
	    ENDP
	    

; R1 = R0 * R1, where R0 and R1 are 16-bit values
; destroys R0, R2, R3, R4, R5
qs_mpy16:   PROC
	    PSHR    R5		  ;   9
				   
	    ; Unpack lo/hi
	    MOVR    R0,	 R2      ;   6   
	    ANDI    #$FF,       R0      ;   8   R0 is lo(a)
	    XORR    R0,	 R2      ;   6   
	    SWAP    R2		  ;   6   R2 is hi(a)

	    MOVR    R1,	 R3      ;   6   R3 is orig 16-bit b
	    ANDI    #$FF,       R1      ;   8   R1 is lo(b)
	    MOVR    R1,	 R5      ;   6   R5 is lo(b)
	    XORR    R1,	 R3      ;   6   
	    SWAP    R3		  ;   6   R3 is hi(b)
					;----
					;  67
					
	    ; lo * lo		   
	    MOVR    R0,	 R4      ;   6   R4 is lo(a)
	    ADDI    #QSQR8_TBL.mid, R1  ;   8
	    ADDR    R1,	 R4      ;   6   R4 = lo(a) + lo(b)
	    SUBR    R0,	 R1      ;   6   R1 = lo(a) - lo(b)
					
@@pos_ll:   MVI@    R4,	 R4      ;   8   R4 = qstbl[lo(a)+lo(b)]
	    SUB@    R1,	 R4      ;   8   R4 = lo(a)*lo(b)
					;----
					;  42
					;  67 (carried forward)
					;----
					; 109
				       
	    ; lo * hi		  
	    MOVR    R0,	 R1      ;   6   R0 = R1 = lo(a)
	    ADDI    #QSQR8_TBL.mid, R3  ;   8
	    ADDR    R3,	 R1      ;   6   R1 = hi(b) + lo(a)
	    SUBR    R0,	 R3      ;   6   R3 = hi(b) - lo(a)
				       
@@pos_lh:   MVI@    R1,	 R1      ;   8   R1 = qstbl[hi(b)-lo(a)]
	    SUB@    R3,	 R1      ;   8   R1 = lo(a)*hi(b)
					;----
					;  42
					; 109 (carried forward)
					;----
					; 151
				       
	    ; hi * lo		  
	    MOVR    R5,	 R0      ;   6   R5 = R0 = lo(b)
	    ADDI    #QSQR8_TBL.mid, R2  ;   8
	    ADDR    R2,	 R5      ;   6   R3 = hi(a) + lo(b)
	    SUBR    R0,	 R2      ;   6   R2 = hi(a) - lo(b)
				       
@@pos_hl:   ADD@    R5,	 R1      ;   8   \_ R1 = lo(a)*hi(b)+hi(a)*lo(b)
	    SUB@    R2,	 R1      ;   8   /
					;----
					;  42
					; 151 (carried forward)
					;----
					; 193
				       
	    SWAP    R1		  ;   6   \_ shift upper product left 8
	    ANDI    #$FF00,     R1      ;   8   /
	    ADDR    R4,	 R1      ;   6   final product
	    PULR    PC		  ;  12
					;----
					;  32
					; 193 (carried forward)
					;----
					; 225
	    ENDP

	ENDI

	IF intybasic_fastdiv

; Fast unsigned division/remainder
; Assembly code by Oscar Toledo G. Jul/10/2015
; Released to public domain.

	; Ultrafast unsigned division/remainder operation
	; Entry: R0 = Dividend
	;	R1 = Divisor
	; Output: R0 = Quotient
	;	 R2 = Remainder
	; Worst case: 6 + 6 + 9 + 496 = 517 cycles
	; Best case: 6 + (6 + 7) * 16 = 214 cycles

uf_udiv16:	PROC
	CLRR R2		; 6
	SLLC R0,1	; 6
	BC @@1		; 7/9
	SLLC R0,1	; 6
	BC @@2		; 7/9
	SLLC R0,1	; 6
	BC @@3		; 7/9
	SLLC R0,1	; 6
	BC @@4		; 7/9
	SLLC R0,1	; 6
	BC @@5		; 7/9
	SLLC R0,1	; 6
	BC @@6		; 7/9
	SLLC R0,1	; 6
	BC @@7		; 7/9
	SLLC R0,1	; 6
	BC @@8		; 7/9
	SLLC R0,1	; 6
	BC @@9		; 7/9
	SLLC R0,1	; 6
	BC @@10		; 7/9
	SLLC R0,1	; 6
	BC @@11		; 7/9
	SLLC R0,1	; 6
	BC @@12		; 7/9
	SLLC R0,1	; 6
	BC @@13		; 7/9
	SLLC R0,1	; 6
	BC @@14		; 7/9
	SLLC R0,1	; 6
	BC @@15		; 7/9
	SLLC R0,1	; 6
	BC @@16		; 7/9
	JR R5

@@1:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@2:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@3:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@4:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@5:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@6:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@7:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@8:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@9:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@10:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@11:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@12:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@13:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@14:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@15:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@16:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
	JR R5
	
	ENDP

	ENDI

	ROM.End

	ROM.OutputRomStats

	ORG $200,$200,"-RWB"

Q2:	; Reserved label for #BACKTAB

	;
	; 16-bits variables
	; Note IntyBASIC variables grow up starting in $308.
	;

BASE_16BIT_SYSTEM_VARS: QSET $33f
    IF intybasic_voice
BASE_16BIT_SYSTEM_VARS: QSET BASE_16BIT_SYSTEM_VARS-10
    ENDI
    IF intybasic_col
BASE_16BIT_SYSTEM_VARS: QSET BASE_16BIT_SYSTEM_VARS-8
    ENDI
    IF intybasic_scroll
BASE_16BIT_SYSTEM_VARS: QSET BASE_16BIT_SYSTEM_VARS-20
    ENDI

	ORG BASE_16BIT_SYSTEM_VARS,BASE_16BIT_SYSTEM_VARS,"-RWB"

    IF intybasic_voice
IV.Q:      RMB 8    ; IV_xxx	16-bit	  Voice queue  (8 words)
IV.FPTR:   RMB 1    ; IV_xxx	16-bit	  Current FIFO ptr.
IV.PPTR:   RMB 1    ; IV_xxx	16-bit	  Current Phrase ptr.
    ENDI
    IF intybasic_col
_col0:      RMB 1       ; Collision status for MOB0
_col1:      RMB 1       ; Collision status for MOB1
_col2:      RMB 1       ; Collision status for MOB2
_col3:      RMB 1       ; Collision status for MOB3
_col4:      RMB 1       ; Collision status for MOB4
_col5:      RMB 1       ; Collision status for MOB5
_col6:      RMB 1       ; Collision status for MOB6
_col7:      RMB 1       ; Collision status for MOB7
    ENDI
    IF intybasic_scroll
_scroll_buffer: RMB 20  ; Sometimes this is unused
    ENDI
_music_gosub:	RMB 1	; GOSUB pointer
_music_table:	RMB 1	; Note table
_music_p:	RMB 1	; Pointer to music
_frame:		RMB 1   ; Current frame
_read:		RMB 1   ; Pointer to DATA
_gram_bitmap:   RMB 1   ; Bitmap for definition
_gram2_bitmap:  RMB 1   ; Secondary bitmap for definition
_screen:	RMB 1	; Pointer to current screen position
_color:		RMB 1	; Current color

Q1:			; Reserved label for #MOBSHADOW
_mobs:      RMB 3*8     ; MOB buffer

SCRATCH:    ORG $100,$100,"-RWBN"
	;
	; 8-bits variables
	;
ISRVEC:     RMB 2       ; Pointer to ISR vector (required by Intellivision ROM)
_int:       RMB 1       ; Signals interrupt received
_ntsc:      RMB 1       ; bit 0 = 1=NTSC, 0=PAL. Bit 1 = 1=ECS detected.
_rand:      RMB 1       ; Pseudo-random value
_gram_target:   RMB 1   ; Contains GRAM card number
_gram_total:    RMB 1   ; Contains total GRAM cards for definition
_gram2_target:  RMB 1   ; Contains GRAM card number
_gram2_total:   RMB 1   ; Contains total GRAM cards for definition
_mode_select:   RMB 1   ; Graphics mode selection
_border_color:  RMB 1   ; Border color
_border_mask:   RMB 1   ; Border mask
    IF intybasic_keypad
_cnt1_p0:   RMB 1       ; Debouncing 1
_cnt1_p1:   RMB 1       ; Debouncing 2
_cnt1_key:  RMB 1       ; Currently pressed key
_cnt2_p0:   RMB 1       ; Debouncing 1
_cnt2_p1:   RMB 1       ; Debouncing 2
_cnt2_key:  RMB 1       ; Currently pressed key
    ENDI
    IF intybasic_scroll
_scroll_x:  RMB 1       ; Scroll X offset
_scroll_y:  RMB 1       ; Scroll Y offset
_scroll_d:  RMB 1       ; Scroll direction
    ENDI
    IF intybasic_music
_music_start:	RMB 2	; Start of music

_music_mode: RMB 1      ; Music mode (0= Not using PSG, 2= Simple, 4= Full, add 1 if using noise channel for drums)
_music_frame: RMB 1     ; Music frame (for 50 hz fixed)
_music_tc:  RMB 1       ; Time counter
_music_t:   RMB 1       ; Time base
_music_i1:  RMB 1       ; Instrument 1 
_music_s1:  RMB 1       ; Sample pointer 1
_music_n1:  RMB 1       ; Note 1
_music_i2:  RMB 1       ; Instrument 2
_music_s2:  RMB 1       ; Sample pointer 2
_music_n2:  RMB 1       ; Note 2
_music_i3:  RMB 1       ; Instrument 3
_music_s3:  RMB 1       ; Sample pointer 3
_music_n3:  RMB 1       ; Note 3
_music_s4:  RMB 1       ; Sample pointer 4
_music_n4:  RMB 1       ; Note 4 (really it's drum)

_music_freq10:	RMB 1   ; Low byte frequency A
_music_freq20:	RMB 1   ; Low byte frequency B
_music_freq30:	RMB 1   ; Low byte frequency C
_music_freq11:	RMB 1   ; High byte frequency A
_music_freq21:	RMB 1   ; High byte frequency B
_music_freq31:	RMB 1   ; High byte frequency C
_music_mix:	RMB 1   ; Mixer
_music_noise:	RMB 1   ; Noise
_music_vol1:	RMB 1   ; Volume A
_music_vol2:	RMB 1   ; Volume B
_music_vol3:	RMB 1   ; Volume C
    ENDI
    IF intybasic_music_ecs
_music_i5:  RMB 1       ; Instrument 5
_music_s5:  RMB 1       ; Sample pointer 5
_music_n5:  RMB 1       ; Note 5
_music_i6:  RMB 1       ; Instrument 6
_music_s6:  RMB 1       ; Sample pointer 6
_music_n6:  RMB 1       ; Note 6
_music_i7:  RMB 1       ; Instrument 7
_music_s7:  RMB 1       ; Sample pointer 7
_music_n7:  RMB 1       ; Note 7
_music_s8:  RMB 1       ; Sample pointer 8
_music_n8:  RMB 1       ; Note 8 (really it's drum)

_music2_freq10:	RMB 1   ; Low byte frequency A
_music2_freq20:	RMB 1   ; Low byte frequency B
_music2_freq30:	RMB 1   ; Low byte frequency C
_music2_freq11:	RMB 1   ; High byte frequency A
_music2_freq21:	RMB 1   ; High byte frequency B
_music2_freq31:	RMB 1   ; High byte frequency C
_music2_mix:	RMB 1   ; Mixer
_music2_noise:	RMB 1   ; Noise
_music2_vol1:	RMB 1   ; Volume A
_music2_vol2:	RMB 1   ; Volume B
_music2_vol3:	RMB 1   ; Volume C
    ENDI
    IF intybasic_music_volume
_music_vol:	RMB 1	; Global music volume
    ENDI
    IF intybasic_voice
IV.QH:     RMB 1    ; IV_xxx	8-bit	   Voice queue head
IV.QT:     RMB 1    ; IV_xxx	8-bit	   Voice queue tail
IV.FLEN:   RMB 1    ; IV_xxx	8-bit	   Length of FIFO data
    ENDI

var_A:	RMB 1	; A
var_C:	RMB 1	; C
var_CURRIGA:	RMB 1	; CURRIGA
var_EMPTYLINES:	RMB 1	; EMPTYLINES
var_I:	RMB 1	; I
var_J:	RMB 1	; J
var_K:	RMB 1	; K
var_LASTRIGA:	RMB 1	; LASTRIGA
var_P:	RMB 1	; P
array_TIPO:	RMB 10	; TIPO
_SCRATCH:	EQU $

SYSTEM:	ORG $2F0, $2F0, "-RWBN"
STACK:	RMB 24
var_&C:	RMB 1	; #C
var_&CNT:	RMB 1	; #CNT
var_&MEM:	RMB 1	; #MEM
_SYSTEM:	EQU $
