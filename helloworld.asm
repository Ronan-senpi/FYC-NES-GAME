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
    PPUADDR     EQU $2006
    PPUDATA     EQU $2007


    ; colors
    BLACK       EQU $3F
    WHITE       EQU $30
    RED         EQU $06
    GREEN       EQU $0A

    ENUM $0000  ; Les variables "rapides"
vbl_count  DS.B 1  ; Compteur de VBL (50 Hz)
vbl_flag DS.B 1  ; Mis à 1 par la VBL
    ENDE

    ; debut de la partie code du programme
    BASE $C000
RESET:
    ; remise a zero du compteur de vbl et du controle & du mask du ppu, ainsi que de l apu
    LDA #0        ; 0 dans l'accumulateur A
    STA vbl_count ; le contenu de A (ici 0) va à l'adresse vbl_count -> 1ere frame
    STA PPUCTRL
    STA PPUMASK
    ; apu
    STA $4010

    LDX #$ff    ; Initialise X à 255
    TXS         ; met x dans la pile -> transfer x to stack pointer

    ; on attend que le ppu soit pret
    BIT PPUSTATUS ; si ppu est prêt, ppustatus sera à 1 et met le bit de zero flag à 1
  - BIT PPUSTATUS
    BNE -   ; loop sur - le plus proche si PPUSTATUS n est pas a 1 -> BNE branche si zero flag = 0 (branch if not equal)

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


    ; on ne peut déplacer que 1 octet à la fois dans PPUADDR, sur nes on doit donc déplacer 2 octets en 2 opérations
    ;; Chargement de la palette de couleurs
    ;; les palettes de 16 couleurs chacunes sont stockées aux adresses $3F00 à $3F1F
    ; on veut déplacer ici #$3F00, la premiere palette
    LDA #$3F    ; On positionne le registre -> ici poids fort
    STA PPUADDR ;   d'adresse du PPU
    LDA #$00    ;   à la valeur $3F00 -> poids faible
    STA PPUADDR

    LDX #0         ; Initialise X à 0
  - LDA palettes,X  ; On charge la Xième couleur (et pas la xieme palette)
    STA PPUDATA    ; pour l'envoyer au PPU
    INX            ; On passe à la couleur suivante -> ++x
    CPX #32        ; Et ce, 32 fois
    BNE -          ; Boucle au - précédent



    ; on remplit la ram du ppu avec les donnees
    LDA PPUSTATUS   ; resynchronisation
    LDA #$20    ; on copie vers $2000 (PPUCTRL) pour le controle general du ppu, ici poids fort
    STA PPUADDR
    LDA #$00    ; poids faible
    STA PPUADDR

    LDX #0
  - LDA nametable,X ; on charge les 256 premiers octets depuis la nametable
    STA PPUDATA
    INX
    BNE -

    TXA               ; Puis 256 zéros
  - STA PPUDATA
    INX
    BNE -

  - STA PPUDATA       ; Et encore 256 zéros
    INX
    BNE -

  - STA PPUDATA       ; Et finalement 192 zéros
    INX
    CPX #192          ; 256 + 256 + 256 + 192 = 960
    BNE -

    BIT PPUSTATUS
  - BIT PPUSTATUS
    BPL -


;; Avant de rebrancher le PPU
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
    PLA ; pull de la pile vers a
    RTI ; interruption

mainloop:
  - LDA vbl_flag
    BEQ -   ; wait for 1 frame
    LDA #0
    STA vbl_flag
  
    ; code du jeu ici

    JMP mainloop

palettes:
  DC.B BLACK,BLACK,WHITE,RED, BLACK,WHITE,WHITE,WHITE, BLACK,WHITE,WHITE,WHITE, BLACK,WHITE,WHITE,WHITE
  DC.B GREEN,BLACK,BLACK,BLACK, GREEN,BLACK,BLACK,BLACK, GREEN,BLACK,BLACK,BLACK, GREEN,BLACK,BLACK,BLACK

nametable:  ; empty space at beginning
  DC.B 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0
  DC.B 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0
  DC.B 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0, "BONJOUR !"   ; pareil que rentrer les codes ascii (fichier de lettres trié)




    ; vecteurs d interruptions du 6502, la nes possède 3 vecteurs d'interruptions, on ne se servira que de RESET et de VBL ici
    ORG $FFFA
    DC.W VBL    ; a chaque debut d image
    DC.W RESET  ; au lancement
    DC.W $00    ; inutilisé

    INCBIN "gfx.chr"