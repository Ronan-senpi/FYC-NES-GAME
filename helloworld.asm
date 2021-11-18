    ; header de 16o pour les emulateurs
    DC.B "NES", $1a
    DC.B 1  ; 1 boitier de 16Ko de rom cpu
    DC.B 1  ; 1 boitier de 8Ko de rom ppu
    DC.B 0  ; type de cartouche
    DS.B 9, $00 ; 9 zeros pour completer les 16o

    ; defines
PPUCTRL     EQU $2000
PPUMASK     EQU $2001
PPUSTATUS   EQU $2002
PPUSCROLL   EQU $2005
PPUADDR     EQU $2006
PPUDATA     EQU $2007


    ; colors
COMMUN      EQU $14
BLACK       EQU $3F
WHITE       EQU $30
RED         EQU $06
GREEN       EQU $0A

    ENUM $0000  ; Les variables "rapides"
vbl_count  DS.B 1  ; Compteur de VBL (50 Hz)
vbl_flag DS.B 1  ; Mis à 1 par la VBL
pointer   DS.W 1  ; Un pointeur pour le remplissage des "nametables"
offset    DS.B 1  ; Le décalage de l'écran
direction DS.B 1  ; Le sens de variation de l'offset
    ENDE

    ; debut de la partie code du programme
    BASE $C000
RESET:
  ; remise a zero du compteur de vbl et du controle & du mask du ppu, ainsi que de l apu
  LDA #0        ; 0 dans l'accumulateur A
  STA vbl_count ; le contenu de A (ici 0) va à l'adresse vbl_count -> 1ere frame
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

  LDX #0         ; Initialise X à 0
- LDA palettes,X ; On charge la Xième couleur (et pas la xieme palette)
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
  LDA PPUSTATUS   ; resynchronisation
  LDA #$20    ; on copie vers $2000 (PPUCTRL) pour le controle general du ppu, ici poids fort
  STA PPUADDR
  LDA #$00    ; poids faible
  STA PPUADDR

  LDA #<nametable ; On initialise notre pointeur
  STA pointer     ;    avec le début des données
  LDA #>nametable ;    nametable + attributs
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
- BIT PPUSTATUS ; on attend une dernière fois
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
  INC vbl_count

  LDA offset    ; On charge notre décalage
  STA PPUSCROLL ;   qui devient la valeur de scrolling en X
  LDA #0        ; Et on met 0 pour la valeur
  STA PPUSCROLL ;   de scrolling en Y

  PLA ; pull de la pile vers a
  RTI ; interruption

mainloop:
- LDA vbl_flag
  BEQ -   ; wait for 1 frame
  LDA #0
  STA vbl_flag

; Mise à jour de l'offset
  LDA direction  ; Si la direction vaut 1
  BNE a_gauche   ; C'est qu'on décale vers la gauche
  CLC            ; Sinon,
  JMP a_droite   ; C'est qu'on décale vers la droite

a_gauche         ; Si on va à gauche,
  SEC            ; Le processus est le même
  LDA offset     ;   dans l'autre sens :
  SBC #3         ;   on soustrait 3
  STA offset
  BNE mainloop   ; Et si on est à 0
  DEC direction  ; On rechange de direction
  JMP mainloop

a_droite
  LDA offset     ; On effectue une addition
  ADC #3         ;   de 3 pixels
  STA offset     ;   sur l'offset
  CMP #255       ; Et si on arrive à 255
  BNE mainloop
  INC direction  ;  ... on change de direction
  JMP mainloop

palettes:
  DC.B COMMUN,BLACK,WHITE,RED, COMMUN,WHITE,WHITE,WHITE, COMMUN,WHITE,WHITE,WHITE, COMMUN,WHITE,WHITE,WHITE
  DC.B COMMUN,BLACK,BLACK,BLACK, COMMUN,BLACK,BLACK,BLACK, COMMUN,BLACK,BLACK,BLACK, COMMUN,BLACK,BLACK,BLACK

nametable:
nametable_0:
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 1,2,5,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 3,4,6,7,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 8,9,12,13,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 10,11,14,15,0,0,0,0
  DC.B 1,2,5,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 3,4,6,7,0,16,0,0, 0,16,0,0,17,18,18,18, 19,0,17,18,18,18,18,19, 0,16,0,0,18,20,0,0
  DC.B 8,9,12,13,0,18,0,0, 0,18,0,0,18,23,0,24, 18,0,18,23,0,0,24,18, 0,18,0,0,18,25,0,0
  DC.B 10,11,14,15,0,18,21,0, 22,18,0,17,18,21,0,22, 18,0,18,0,0,0,0,0, 0,18,21,0,18,0,0,0
  DC.B 0,0,0,0,17,18,18,18, 18,18,0,18,18,18,18,18, 18,0,18,16,0,0,0,0, 0,18,18,18,18,18,19,0
  DC.B 0,0,0,0,18,18,23,0, 24,18,0,18,18,23,0,24, 18,0,18,18,21,0,22,18, 0,18,23,0,24,18,18,0
  DC.B 0,0,0,0,26,18,0,0, 0,18,0,27,18,0,0,0, 18,0,26,18,18,18,18,28, 0,18,0,0,0,18,18,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,1,2,5,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,3,4,6,7, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,8,9,12,13, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,10,11,14,15, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 29,30,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,29,30
  DC.B 31,32,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,31,32
  DC.B 33,34,29,30,0,0,0,0, 1,2,5,0,0,0,0,0, 0,0,0,0,1,2,5,0, 0,0,0,0,29,30,33,34
  DC.B 31,32,31,32,0,0,0,0, 3,4,6,7,0,0,0,0, 0,0,0,0,3,4,6,7, 0,0,0,0,31,32,31,32
  DC.B 33,34,33,34,29,30,29,30, 29,30,29,30,29,30,29,30, 29,30,29,30,29,30,29,30, 29,30,29,30,29,30,29,30
  DC.B 31,32,31,32,31,32,31,32, 31,32,31,32,31,32,31,32, 31,32,31,32,31,32,31,32, 31,32,31,32,31,32,31,32
  DC.B 33,34,33,34,33,34,33,34, 33,34,33,34,33,34,33,34, 33,34,33,34,33,34,33,34, 33,34,33,34,33,34,33,34
  DC.B 31,32,31,32,31,32,31,32, 31,32,31,32,31,32,31,32, 31,32,31,32,31,32,31,32, 31,32,31,32,31,32,31,32
  DC.B 33,34,33,34,33,34,33,34, 33,34,33,34,33,34,33,34, 33,34,33,34,33,34,33,34, 33,34,33,34,33,34,33,34
  DC.B 31,32,31,32,31,32,31,32, 31,32,31,32,31,32,31,32, 31,32,31,32,31,32,31,32, 31,32,31,32,31,32,31,32
attribute_0:
  DC.B 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0
  DC.B 162,0,80,0,0,80,0,168
  DC.B 170,170,170,170,170,170,170,170
  DC.B 10,10,10,10,10,10,10,10
nametable_1:
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 1,2,5,0,0,0,0,0, 0,0,0,0,1,2,5,0
  DC.B 0,17,18,18,18,19,0,17, 18,18,19,0,0,0,16,0, 3,4,6,7,0,17,18,18, 18,18,16,0,3,4,6,7
  DC.B 0,18,23,0,24,18,0,18, 35,36,18,21,0,0,18,0, 8,9,12,13,0,18,35,0, 0,0,0,0,8,9,12,13
  DC.B 17,18,21,0,22,18,0,18, 18,18,18,18,19,0,18,0, 10,11,14,15,0,18,18,18, 16,0,0,0,10,11,14,15
  DC.B 18,18,18,18,18,18,0,18, 37,0,24,18,18,0,18,16, 0,0,0,0,0,18,18,23, 0,0,0,0,0,0,0,0
  DC.B 18,18,23,0,24,18,0,18, 21,0,22,18,18,0,18,18, 21,0,22,18,0,18,18,21, 0,0,0,0,0,0,0,0
  DC.B 27,18,0,0,0,18,0,26, 18,18,18,18,28,0,26,18, 18,18,18,28,0,26,18,18, 18,18,16,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
  DC.B 38,38,38,38,38,38,38,38, 38,38,38,38,29,30,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,29,30
  DC.B 38,38,38,38,38,38,38,38, 38,38,38,38,31,32,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,31,32
  DC.B 38,38,38,38,38,38,38,38, 38,38,38,38,33,34,29,30, 1,2,5,0,0,0,0,0, 0,0,0,0,29,30,33,34
  DC.B 38,38,38,38,38,38,38,38, 38,38,38,38,31,32,31,32, 3,4,6,7,0,0,0,0, 0,0,0,0,31,32,31,32
  DC.B 29,30,29,30,29,30,29,30, 29,30,29,30,29,30,29,30, 29,30,29,30,29,30,29,30, 29,30,29,30,33,34,33,34
  DC.B 31,32,31,32,31,32,31,32, 31,32,31,32,31,32,31,32, 31,32,31,32,31,32,31,32, 31,32,31,32,31,32,31,32
  DC.B 33,34,33,34,33,34,33,34, 33,34,33,34,33,34,33,34, 33,34,33,34,33,34,33,34, 33,34,33,34,33,34,33,34
  DC.B 31,32,31,32,31,32,31,32, 31,32,31,32,31,32,31,32, 31,32,31,32,31,32,31,32, 31,32,31,32,31,32,31,32
  DC.B 33,34,33,34,33,34,33,34, 33,34,33,34,33,34,33,34, 33,34,33,34,33,34,33,34, 33,34,33,34,33,34,33,34
  DC.B 31,32,31,32,31,32,31,32, 31,32,31,32,31,32,31,32, 31,32,31,32,31,32,31,32, 31,32,31,32,31,32,31,32
attribute_1:
  DC.B 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0
  DC.B 0,0,0,0,0,0,0,0
  DC.B 255,255,255,162,80,0,0,168
  DC.B 170,170,170,170,170,170,170,170
  DC.B 10,10,10,10,10,10,10,10

; vecteurs d interruptions du 6502, la nes possède 3 vecteurs d'interruptions, on ne se servira que de RESET et de VBL ici
  ORG $FFFA
  DC.W VBL    ; a chaque debut d image
  DC.W RESET  ; au lancement
  DC.W $00    ; inutilisé

  INCBIN "gfx.chr"