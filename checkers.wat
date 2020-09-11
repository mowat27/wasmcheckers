;; Checkerboard has 64 squares (8x8 grid)

;; Unoccupied square -  00000000
;; Black Occupied    -  00000001 - 1
;; White Occupied    -  00000010 - 2
;; Crowned or Kinged -  00000100 - 4
;; e.g. crowned white - 6, crowned black - 5

(module
  ;; Host-provided functions
  (import "events" "piecemoved" 
    (func $notify_piecemoved (param $fromX i32)
                             (param $fromY i32)
                             (param $toX i32)
                             (param $toY i32)))

  (import "events" "piececrowned" 
    (func $notify_piececrowned (param $pieceX i32)
                               (param $pieceY i32)))


  ;; Using bit flgs to track the state of a square on the board
  (global $BLACK i32 (i32.const 1))
  (global $WHITE i32 (i32.const 2))
  (global $CROWN i32 (i32.const 4))
  (global $currentTurn (mut i32) (i32.const 0))

  ;; Declare a single block of memory for the game
  (memory $mem 1)
  
  (func $indexForPosition (param $x i32) (param $y i32) (result i32)
    (i32.add 
      (i32.mul (i32.const 8) (get_local $y)
      (get_local $x))))

  ;; Finds a board position in linear memory
  ;; Offset = (x + y * 8) * 4 because there are 4 bytes in an i32
  (func $offsetForPosition (param $x i32) (param $y i32) (result i32)
    (i32.mul 
      (call $indexForPosition (get_local $x) (get_local $y))
      (i32.const 4)))

  ;; --------------------------------------------------------------------------
  ;; AND state of piece to find if it is white, black and crowned
  (func $isCrowned (param $piece i32) (result i32)
    (i32.eq 
      (i32.and (get_local $piece) (get_global $CROWN)) 
      (get_global $CROWN)))

  (func $isWhite (param $piece i32) (result i32)
    (i32.eq 
      (i32.and (get_local $piece) (get_global $WHITE))  
      (get_global $WHITE)))

  (func $isBlack (param $piece i32) (result i32)
    (i32.eq 
      (i32.and (get_local $piece) (get_global $BLACK)) 
      (get_global $BLACK)))

  ;; --------------------------------------------------------------------------
  ;; Crown and de-crown a piece
  (func $withCrown (param $piece i32) (result i32)
    (i32.or (get_local $piece) (get_global $CROWN)))

  (func $withoutCrown (param $piece i32) (result i32)
    (i32.or (get_local $piece) (i32.const 3)))

  ;; --------------------------------------------------------------------------
  ;; Move pieces

  (func $move (param $fromX i32)
              (param $fromY i32)
              (param $toX i32)
              (param $toY i32)
              (result i32)
    (if (result i32)
      (block (result i32)
        (call $isValidMove (get_local $fromX) 
                           (get_local $fromY) 
                           (get_local $toX) 
                           (get_local $toY)))
        (then 
          (call $do_move (get_local $fromX)
                         (get_local $fromY)
                         (get_local $toX)
                         (get_local $toY)))
        (else 
          (i32.const 0))))

  (func $do_move (param $fromX i32)
                 (param $fromY i32)
                 (param $toX i32)
                 (param $toY i32)
                 (result i32)
    (local $currpiece i32)
    (set_local $currpiece (call $getPiece (get_local $fromX) (get_local $fromY)))
    (call $toggleTurnOwner)
    (call $setPiece (get_local $toX) (get_local $toY) (get_local $currpiece))
    (call $setPiece (get_local $fromX) (get_local $fromY) (i32.const 0))
    (if (call $shouldCrown (get_local $toY) (get_local $currpiece))
      (then 
        (call $crownPiece (get_local $toX) (get_local $toY))))
    (call $notify_piecemoved (get_local $fromX)
                             (get_local $fromY)
                             (get_local $toX)
                             (get_local $toY))
    (i32.const 1))

  (func $setPiece (param $x i32) (param $y i32) (param $piece i32)
    (i32.store 
      (call $offsetForPosition 
        (get_local $x)
        (get_local $y)
      (get_local $piece))))
  
  (func $getPiece (param $x i32) (param $y i32) (result i32)
    (if (result i32) 
      (block (result i32)
        (i32.and (call $inRange (i32.const 0) (i32.const 7) (get_local $x))
                 (call $inRange (i32.const 0) (i32.const 7) (get_local $y))))
      (then 
        (i32.load 
          (call $offsetForPosition (get_local $x) (get_local $y))))
      (else
        (unreachable))))

  ;; Detect whether a number is in a range
  (func $inRange (param $low i32) (param $high i32) (param $value i32) (result i32)
    (i32.and 
      (i32.ge_s (get_local $value) (get_local $low))
      (i32.le_s (get_local $value) (get_local $high))))

  (func $isValidMove (param $fromX i32)
                     (param $fromY i32)
                     (param $toX i32)
                     (param $toY i32)
                     (result i32)
    (local $player i32)
    (local $target i32)
    (set_local $player (call $getPiece (get_local $fromX) (get_local $fromY)))    
    (set_local $target (call $getPiece (get_local $toX) (get_local $toY)))  
    (if (result i32)
      (block (result i32)
        (i32.and 
          (call $validJumpDistance (get_local $fromY) (get_local $toY))
          (i32.and 
              (call $isPlayersTurn (get_local $player)
              ;; Check target is not occupied
              (i32.eq (get_local $target) (i32.const 0))))))
      (then (i32.const 1))
      (else (i32.const 0))))

  (func $validJumpDistance (param $from i32)
                           (param $to i32)
                           (result i32)
    (local $d i32)
    (set_local $d 
      (if (result i32) 
        (i32.gt_s (get_local $to) (get_local $from))
        (then ;; up the board
          (call $distance (get_local $to) (get_local $from))) 
        (else ;; down the board
          (call $distance (get_local $from) (get_local $to))))) 
    (i32.le_u 
      (get_local $d)
      (i32.const 2)))

  ;; --------------------------------------------------------------------------
  ;; Manage players' turns
  (func $getTurnOwner (result i32)
    (get_global $currentTurn))

  (func $setTurnOwner (param $player i32)
    (set_global $currentTurn (get_local $player)))

  (func $toggleTurnOwner
    (if (i32.eq (call $getTurnOwner) (i32.const 1))
      (then (call $setTurnOwner (i32.const 2)))
      (else (call $setTurnOwner (i32.const 1)))))

  (func $isPlayersTurn (param $player i32) (result i32)
    (i32.gt_s 
      (i32.and (get_local $player) (call $getTurnOwner))
      (i32.const 0)))

  ;; --------------------------------------------------------------------------
  ;; Game rules
  (func $shouldCrown (param $pieceY i32) (param $piece i32) (result i32)
    (i32.or
      (i32.and 
        (i32.eq (get_local $pieceY) (i32.const 0))
        (call $isBlack (get_local $piece)))
      (i32.and 
        (i32.eq (get_local $pieceY) (i32.const 7))
        (call $isWhite (get_local $piece)))))

  ;; Crowns a piece and notifies an imported handler of the corination
  (func $crownPiece (param $x i32) (param $y i32)
    (local $piece i32)
    (set_local $piece (call $getPiece (get_local $x) (get_local $y)))
    (call $setPiece (get_local $x) (get_local $y) (call $withCrown (get_local $piece)))
    (call $notify_piececrowned (get_local $x) (get_local $y)))

  (func $distance (param $x i32) (param $y i32) (result i32)
    (i32.sub (get_local $x) (get_local $y)))

  ;; --------------------------------------------------------------------------
  ;; Setup Initial Board State
  (func $initBoard
    ;; Place the white pieces at the top of the board
    (call $setPiece (i32.const 1) (i32.const 0) (i32.const 2))
    (call $setPiece (i32.const 3) (i32.const 0) (i32.const 2))
    (call $setPiece (i32.const 5) (i32.const 0) (i32.const 2))
    (call $setPiece (i32.const 7) (i32.const 0) (i32.const 2))

    (call $setPiece (i32.const 0) (i32.const 1) (i32.const 2))
    (call $setPiece (i32.const 2) (i32.const 1) (i32.const 2))
    (call $setPiece (i32.const 4) (i32.const 1) (i32.const 2))
    (call $setPiece (i32.const 6) (i32.const 1) (i32.const 2))

    (call $setPiece (i32.const 1) (i32.const 2) (i32.const 2))
    (call $setPiece (i32.const 3) (i32.const 2) (i32.const 2))
    (call $setPiece (i32.const 5) (i32.const 2) (i32.const 2))
    (call $setPiece (i32.const 7) (i32.const 2) (i32.const 2))

    ;; Place the black pieces at the bottom of the board
    (call $setPiece (i32.const 0) (i32.const 5) (i32.const 1))
    (call $setPiece (i32.const 2) (i32.const 5) (i32.const 1))
    (call $setPiece (i32.const 4) (i32.const 5) (i32.const 1))
    (call $setPiece (i32.const 6) (i32.const 5) (i32.const 1))

    (call $setPiece (i32.const 1) (i32.const 6) (i32.const 1))
    (call $setPiece (i32.const 3) (i32.const 6) (i32.const 1))
    (call $setPiece (i32.const 5) (i32.const 6) (i32.const 1))
    (call $setPiece (i32.const 7) (i32.const 6) (i32.const 1))

    (call $setPiece (i32.const 0) (i32.const 7) (i32.const 1))
    (call $setPiece (i32.const 2) (i32.const 7) (i32.const 1))
    (call $setPiece (i32.const 4) (i32.const 7) (i32.const 1))
    (call $setPiece (i32.const 6) (i32.const 7) (i32.const 1))

    (call $setTurnOwner (i32.const 1)) ;; Black goes first
  )

  ;; --------------------------------------------------------------------------
  ;; Exports
  (export "getPiece" (func $getPiece))
  (export "isCrowned" (func $isCrowned))
  (export "initBoard" (func $initBoard))
  (export "getTurnOwner" (func $getTurnOwner))
  (export "move" (func $move))
  (export "memory" (memory $mem))
)
  
