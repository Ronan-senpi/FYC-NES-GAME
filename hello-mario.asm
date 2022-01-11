    ; defines
PPUCTRL   EQU $2000
PPUMASK   EQU $2001
PPUSTATUS EQU $2002
OAMADDR   EQU $2003
OAMDATA   EQU $2004
PPUSCROLL EQU $2005
PPUADDR   EQU $2006
PPUDATA   EQU $2007
JOYPAD1   EQU $4016


    ENUM $0000  ; Les variables "rapides"
vbl_cnt  DS.B 1  ; Compteur de VBL (50 Hz)
vbl_flag DS.B 1  ; Mis à 1 par la VBL
pointer   DS.W 1  ; Un pointeur pour le remplissage des "nametables"
offset    DS.B 1  ; Le décalage de l'écran
direction DS.B 1  ; Le sens de variation de l'offset
    ENDE

    ; header de 16o pour les emulateurs
    DC.B "NES", $1a
    DC.B 1  ; 1 boitier de 16Ko de rom cpu
    DC.B 1  ; 1 boitier de 8Ko de rom ppu
    DC.B 1  ; type de cartouche
    DS.B 9, $00 ; 9 zeros pour completer les 16o

    ; debut de la partie code du programme
    BASE $C000
RESET:
  ; remise a zero du compteur de vbl et du controle & du mask du ppu, ainsi que de l apu
  LDA #0        ; 0 dans l'accumulateur A
  STA vbl_cnt ; le contenu de A (ici 0) va à l'adresse vbl_count -> 1ere frame
  STA PPUCTRL   ; du Controle du PPU
  STA PPUMASK   ; du Mask du PPU
  STA $4010     ; et de
  LDA #$40      ;   tout
  STA $4017     ;     l'APU

  LDX #$ff    ; Initialise X à 255
  TXS         ; met x dans la pile -> transfer x to stack pointer

  ; on attend que le ppu soit pret
  BIT PPUSTATUS ; si ppu est prêt, ppustatus sera à 1 et met le bit de zero flag à 1
- BIT PPUSTATUS
  BPL -   ; loop sur - le plus proche si PPUSTATUS n est pas a 1 -> BNE branche si zero flag = 0 (branch if not equal)

  ; on remet a zero la ram (2Ko)
  LDA #0
  TAX ; Transfer A to X donc X = 0
- STA $0000,X ; 0 a l adresse 0 + x
  STA $0100,X ; 256 + x
  STA $0200,X ; 512 + x
  STA $0300,X ; 768 + x
  STA $0400,X ; 1024 + x
  STA $0500,X ; 1280 + x
  STA $0600,X ; 1536 + x
  STA $0700,X ; 1792 + x
  INX ; incremente x donc boucle suivante sera sur $0001, $0101, etc
  BNE - ; si x != 0 loop sur - (permet de loop x sur 1 octet pour parcourir toutes les adresses puis x revient à 0)

  ; On attend encore un peu le PPU, au cas où
  LDA PPUSTATUS

  ; on ne peut déplacer que 1 octet à la fois dans PPUADDR, sur nes on doit donc déplacer 2 octets en 2 opérations
  ; Chargement de la palette de couleurs
  ; les palettes de 16 couleurs chacunes sont stockées aux adresses $3F00 à $3F1F
  ; on veut déplacer ici #$3F00, la premiere palette
  LDA #$3F    ; On positionne le registre -> ici poids fort
  STA PPUADDR ;   d'adresse du PPU
  LDA #$00    ;   à la valeur $3F00 -> poids faible
  STA PPUADDR

  LDX #3        ; Initialise X à 0
- LDA palette,X ; On charge la Xième couleur (et pas la xieme palette)
  STA PPUDATA    ; pour l'envoyer au PPU
  INX            ; On passe à la couleur suivante -> ++x
  CPX #32        ; Et ce, 32 fois
  BNE -          ; Boucle au - précédent

  ; Effaçage des attributs 
  ;(les inforamations de coleurs du bg en fonction de bloc de 16x16)
  LDA PPUSTATUS  ; On se resynchronise
  LDA #$23       ; Le registre d'adresse PPU
  STA PPUADDR    ;   est chargé avec la valeur
  LDA #$C0       ;   $23C0
  STA PPUADDR    ;   (attributs de la nametable 0)

  LDA #0         ; Initialise A
  TAX            ;   et X à zéro
- STA PPUDATA    ;   0 est envoyé au PPU
  INX            ; Et on boucle
  CPX #64        ;   64 fois
  BNE -

; on remplit la ram du ppu avec les donnees
 ;; Affichage du fond (nametable_)
  LDA PPUSTATUS  ; Resynchronisation
  LDA #$20       ;   On copie maintenant
  STA PPUADDR    ;     vers l'adresse $2000
  LDA #$00
  STA PPUADDR

  LDA #<nametables ; On initialise notre pointeur
  STA pointer     ;    avec le début des données
  LDA #>nametables ;    nametables + attributs
  STA pointer+1

  LDX #0            ; X = compteur de pages de 256 octes
  LDY #0            ; Y = décalage dans une page
- LDA (pointer),Y   ; On récupère la Yième donnée
  STA PPUDATA       ;   que l'on transmet au PPU
  INY               ; Passage à la donnée suivante
  BNE -             ; Jusqu'à Y = 256 (== 0)
  INC pointer+1     ; Sinon on incrémente le poids fort du pointeur
  INX               ; Et on passe à la page suivante
  CPX #8            ; Pendant 8 pages (8 * 256 = 2 Ko)
  BNE -

  BIT PPUSTATUS ; Resynchronisation
- BIT PPUSTATUS ; On attend une dernière fois
  BPL -

  ; Avant de rebrancher le PPU
  LDA #%10010000 ; Réactivation, avec les tuiles de fond en $1000
  STA PPUCTRL
  LDA #%00011110 ; On veut montrer le fond au moins
  STA PPUMASK

  JMP mainloop


VBL:
  PHA ; push de a vers la pile
  LDA #1
  STA vbl_flag
  INC vbl_cnt

  JSR draw_mario

  LDA offset    ; On charge notre décalage
  STA PPUSCROLL ;   qui devient la valeur de scrolling en X
  LDA #0        ; Et on met 0 pour la valeur
  STA PPUSCROLL ;   de scrolling en Y
  PLA ; pull de la pile vers a
  RTI ; interruption

;; La boucle principale du programme
mainloop:
- LDA vbl_flag ; On a attend que la VBL ait lieu
  BEQ -
  LDA #0       ; et on réinitialise le drapeau
  STA vbl_flag

;; Mise à jour de l'offset
  LDA direction  ; Si la direction vaut 1
  BNE a_gauche   ; C'est qu'on décale vers la gauche
  CLC            ; Sinon,
  LDA offset     ; On effectue une addition
  ADC #3         ;   de 3 pixels
  STA offset     ;   sur l'offset
  CMP #255       ; Et si on arrive à 255
  BNE mainloop
  INC direction  ;  ... on change de direction
  JMP mainloop
a_gauche         ; Si on va à gauche,
  SEC            ; Le processus est le même
  LDA offset     ;   dans l'autre sens :
  SBC #3         ;   on soustrait 3
  STA offset
  BNE mainloop   ; Et si on est à 0
  DEC direction  ; On rechange de direction
  JMP mainloop

draw_mario:
  LDA #0
  STA OAMADDR
 
  LDA #128     ; Position en Y (en pixel)
  STA OAMDATA
  LDA #$32     ; Adresse de la tile (en hex)
  STA OAMDATA 
  LDA #$2       ; La palette utilisé
  STA OAMDATA 
  LDA #128     ; Position en X (en pixel)
  STA OAMDATA
 
  LDA #128     ; Y
  STA OAMDATA
  LDA #$33
  STA OAMDATA ; Tile
  LDA #$2
  STA OAMDATA ; Attr
  LDA #136     ; X
  STA OAMDATA
 
  LDA #136     ; Y
  STA OAMDATA
  LDA #$42
  STA OAMDATA ; Tile
  LDA #$2
  STA OAMDATA ; Attr
  LDA #128     ; X
  STA OAMDATA
 
  LDA #136     ; Y
  STA OAMDATA
  LDA #$43
  STA OAMDATA ; Tile
  LDA #$2
  STA OAMDATA ; Attr
  LDA #136     ; X
  STA OAMDATA
 
  RTS
  
.include "palette.asm"
.include "nametables.asm"

; vecteurs d interruptions du 6502, la nes possède 3 vecteurs d'interruptions, on ne se servira que de RESET et de VBL ici
  ORG $FFFA
  DC.W VBL    ; a chaque debut d image
  DC.W RESET  ; au lancement
  DC.W $00    ; inutilisé

  INCBIN "mario.chr"