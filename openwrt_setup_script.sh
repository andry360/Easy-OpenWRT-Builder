#!/bin/bash

# Script per l'automazione della configurazione di Debian WSL2 per Easy-OpenWRT-Builder
# Versione: 1.0
# Compatibile con: WSL2 Debian su Windows 11 Pro 24H2
# Il comando per lanciare questo script da github è: bash -c "$(wget -qLO - https://raw.githubusercontent.com/andry360/Easy-OpenWRT-Builder/refs/heads/main/openwrt_setup_script.sh)"
set -e

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funzione per stampare messaggi colorati
print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Funzione per verificare se siamo in WSL
check_wsl() {
    if [[ ! -f /proc/version ]] || ! grep -qi "microsoft\|wsl" /proc/version; then
        print_error "Questo script è progettato per funzionare solo in WSL2!"
        exit 1
    fi
    print_success "WSL2 rilevato correttamente"
}

# Funzione per verificare e installare Git
setup_git() {
    print_step "Verifica e installazione di Git..."
    
    if command -v git &> /dev/null; then
        print_success "Git è già installato: $(git --version)"
        return 0
    fi
    
    print_warning "Git non è installato"
    read -p "Vuoi installare Git ora? [Y/n]: " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        print_info "Aggiornamento della lista dei pacchetti..."
        sudo apt update
        
        print_info "Installazione di Git..."
        if sudo apt install -y git; then
            print_success "Git installato con successo: $(git --version)"
        else
            print_error "Installazione di Git fallita!"
            print_warning "Dovrai clonare manualmente il repository dopo aver configurato l'ambiente"
            print_warning "Comando: git clone https://github.com/andry360/Easy-OpenWRT-Builder.git"
            return 1
        fi
    else
        print_warning "Git non installato. Dovrai clonare manualmente il repository"
        return 1
    fi
}

# Funzione per configurare WSL2
configure_wsl() {
    print_step "Configurazione di WSL2 per rimuovere i percorsi Windows dal PATH..."
    
    if grep -q "appendWindowsPath = false" /etc/wsl.conf 2>/dev/null; then
        print_success "Configurazione WSL2 già presente"
        return 0
    fi
    
    print_info "Creazione/modifica del file /etc/wsl.conf..."
    sudo tee -a /etc/wsl.conf << 'EOF' > /dev/null
[interop]
appendWindowsPath = false
EOF
    
    print_success "Configurazione WSL2 completata"
    print_warning "IMPORTANTE: Dopo la configurazione della cartella case-sensitive, dovrai riavviare WSL2"
    print_warning "Comandi da eseguire dopo questo script:"
    print_warning "1. Esci da WSL2 (exit)"
    print_warning "2. Da PowerShell: wsl --shutdown"
    print_warning "3. Da PowerShell: wsl -d Debian"
}

# Funzione per gestire la cartella del progetto
setup_project_folder() {
    print_step "Configurazione della cartella del progetto..."
    
    echo "Scegli un'opzione:"
    echo "1. Creare una nuova cartella"
    echo "2. Utilizzare una cartella esistente"
    
    read -p "Inserisci la tua scelta [1-2]: " choice
    
    case $choice in
        1)
            read -p "Inserisci il nome della nuova cartella: " folder_name
            if [[ -z "$folder_name" ]]; then
                print_error "Nome cartella non può essere vuoto"
                return 1
            fi
            
            if [[ -d "$folder_name" ]]; then
                print_error "La cartella '$folder_name' esiste già"
                return 1
            fi
            
            mkdir -p "$folder_name"
            PROJECT_DIR="$(pwd)/$folder_name"
            print_success "Cartella '$folder_name' creata: $PROJECT_DIR"
            ;;
        2)
            read -p "Inserisci il percorso della cartella esistente: " existing_folder
            if [[ -z "$existing_folder" ]]; then
                print_error "Percorso cartella non può essere vuoto"
                return 1
            fi
            
            # Risolvi il percorso relativo/assoluto
            if [[ "$existing_folder" = /* ]]; then
                PROJECT_DIR="$existing_folder"
            else
                PROJECT_DIR="$(pwd)/$existing_folder"
            fi
            
            if [[ ! -d "$PROJECT_DIR" ]]; then
                print_error "La cartella '$PROJECT_DIR' non esiste"
                return 1
            fi
            
            # Verifica che la cartella sia vuota
            if [[ -n "$(ls -A "$PROJECT_DIR" 2>/dev/null)" ]]; then
                print_error "La cartella '$PROJECT_DIR' non è vuota"
                print_info "Contenuto della cartella:"
                ls -la "$PROJECT_DIR"
                return 1
            fi
            
            print_success "Cartella esistente selezionata: $PROJECT_DIR"
            ;;
        *)
            print_error "Scelta non valida"
            return 1
            ;;
    esac
    
    # Verifica che la cartella sia accessibile
    if [[ ! -w "$PROJECT_DIR" ]]; then
        print_error "Non hai i permessi di scrittura per la cartella '$PROJECT_DIR'"
        return 1
    fi
    
    echo "PROJECT_DIR=$PROJECT_DIR" > /tmp/openwrt_project_path
    export PROJECT_DIR
}

# Funzione per configurare percorsi case sensitive
configure_case_sensitivity() {
    print_step "Configurazione case sensitive per la cartella del progetto..."
    
    if [[ -z "$PROJECT_DIR" ]]; then
        if [[ -f /tmp/openwrt_project_path ]]; then
            source /tmp/openwrt_project_path
        else
            print_error "Percorso del progetto non trovato"
            return 1
        fi
    fi
    
    # Converti il percorso WSL in percorso Windows
    WINDOWS_PATH=$(wslpath -w "$PROJECT_DIR")
    
    print_warning "IMPORTANTE: Il prossimo passaggio deve essere eseguito da PowerShell in Windows!"
    print_warning "OpenWRT Imagebuilder richiede un filesystem case-sensitive"
    echo
    print_info "Segui questi passaggi:"
    echo "1. Apri PowerShell come Amministratore in Windows"
    echo "2. Esegui il seguente comando:"
    echo
    echo -e "${GREEN}fsutil.exe file setCaseSensitiveInfo \"$WINDOWS_PATH\" enable${NC}"
    echo
    echo "3. Dopo aver eseguito il comando in PowerShell, torna qui e premi Y per continuare"
    echo
    
    while true; do
        read -p "Hai eseguito il comando fsutil in PowerShell? [Y/n]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            print_success "Configurazione case-sensitivity completata"
            break
        elif [[ $REPLY =~ ^[Nn]$ ]]; then
            print_warning "Configurazione case-sensitivity rimandata"
            print_warning "Ricorda di eseguire il comando prima di utilizzare lo script OpenWRT"
            return 1
        else
            print_warning "Inserisci Y per sì o N per no"
        fi
    done
}

# Funzione per clonare il repository
clone_repository() {
    print_step "Clonazione del repository Easy-OpenWRT-Builder..."
    
    if [[ -z "$PROJECT_DIR" ]]; then
        if [[ -f /tmp/openwrt_project_path ]]; then
            source /tmp/openwrt_project_path
        else
            print_error "Percorso del progetto non trovato"
            return 1
        fi
    fi
    
    if ! command -v git &> /dev/null; then
        print_error "Git non è disponibile. Clonazione del repository saltata"
        print_info "Clona manualmente il repository con:"
        print_info "cd \"$PROJECT_DIR\""
        print_info "git clone https://github.com/andry360/Easy-OpenWRT-Builder.git ."
        return 1
    fi
    
    print_info "Clonazione in corso in: $PROJECT_DIR"
    if git clone https://github.com/andry360/Easy-OpenWRT-Builder.git "$PROJECT_DIR/Easy-OpenWRT-Builder"; then
        print_success "Repository clonato con successo"
        
        # Sposta i file dalla sottocartella alla cartella principale
        print_info "Spostamento dei file nella cartella del progetto..."
        mv "$PROJECT_DIR/Easy-OpenWRT-Builder"/* "$PROJECT_DIR/"
        mv "$PROJECT_DIR/Easy-OpenWRT-Builder"/.* "$PROJECT_DIR/" 2>/dev/null || true
        rmdir "$PROJECT_DIR/Easy-OpenWRT-Builder"
        
        print_success "File spostati nella cartella del progetto"
    else
        print_error "Clonazione del repository fallita"
        return 1
    fi
}

# Funzione per impostare i permessi
set_permissions() {
    print_step "Impostazione dei permessi di esecuzione..."
    
    if [[ -z "$PROJECT_DIR" ]]; then
        if [[ -f /tmp/openwrt_project_path ]]; then
            source /tmp/openwrt_project_path
        else
            print_error "Percorso del progetto non trovato"
            return 1
        fi
    fi
    
    SCRIPT_PATH="$PROJECT_DIR/x86-imagebuilder.sh"
    
    if [[ ! -f "$SCRIPT_PATH" ]]; then
        print_error "Script x86-imagebuilder.sh non trovato in: $SCRIPT_PATH"
        print_warning "Verifica che il repository sia stato clonato correttamente"
        return 1
    fi
    
    chmod +x "$SCRIPT_PATH"
    print_success "Permessi di esecuzione impostati per x86-imagebuilder.sh"
}

# Funzione per mostrare il riepilogo finale
show_summary() {
    print_step "Riepilogo della configurazione completata"
    echo
    print_success "✅ Configurazione completata con successo!"
    echo
    print_info "Percorso del progetto: $PROJECT_DIR"
    print_info "Script principale: $PROJECT_DIR/x86-imagebuilder.sh"
    echo
    print_warning "PROSSIMI PASSAGGI IMPORTANTI:"
    echo "1. Esci da WSL2 digitando: exit"
    echo "2. Da PowerShell in Windows: wsl --shutdown"
    echo "3. Da PowerShell in Windows: wsl -d Debian"
    echo "4. Naviga nella cartella del progetto: cd \"$PROJECT_DIR\""
    echo "5. Esegui lo script OpenWRT: ./x86-imagebuilder.sh"
    echo
    print_info "Per modificare i pacchetti personalizzati, modifica la sezione CUSTOM_PACKAGES"
    print_info "all'inizio del file x86-imagebuilder.sh prima di eseguirlo"
    echo
    print_success "Buona costruzione delle immagini OpenWRT! 🚀"
}

# Funzione principale
main() {
    echo "=================================================="
    echo "   Setup Automatico Easy-OpenWRT-Builder"
    echo "   per WSL2 Debian su Windows 11 Pro 24H2"
    echo "=================================================="
    echo
    
    # Verifica WSL
    check_wsl
    
    # Step 1: Git
    GIT_AVAILABLE=true
    if ! setup_git; then
        GIT_AVAILABLE=false
    fi
    
    # Step 2: Configurazione WSL2
    configure_wsl
    
    # Step 3: Cartella del progetto
    if ! setup_project_folder; then
        print_error "Impossibile configurare la cartella del progetto"
        exit 1
    fi
    
    # Step 4: Case sensitivity
    if ! configure_case_sensitivity; then
        print_warning "Configurazione case-sensitivity non completata"
        print_warning "Ricorda di eseguire il comando fsutil prima di usare lo script OpenWRT"
    fi
    
    # Step 5: Clonazione repository (solo se Git è disponibile)
    if [[ "$GIT_AVAILABLE" == true ]]; then
        if ! clone_repository; then
            print_warning "Repository non clonato. Dovrai farlo manualmente"
        fi
    else
        print_warning "Git non disponibile. Clona manualmente il repository:"
        print_info "cd \"$PROJECT_DIR\""
        print_info "git clone https://github.com/andry360/Easy-OpenWRT-Builder.git ."
    fi
    
    # Step 6: Permessi (solo se il file esiste)
    if [[ -f "$PROJECT_DIR/x86-imagebuilder.sh" ]]; then
        set_permissions
    else
        print_warning "Script x86-imagebuilder.sh non trovato. Imposta i permessi manualmente dopo la clonazione:"
        print_info "chmod +x x86-imagebuilder.sh"
    fi
    
    # Riepilogo finale
    show_summary
    
    # Pulizia
    rm -f /tmp/openwrt_project_path
}

# Gestione degli errori
trap 'print_error "Script interrotto"; exit 1' INT TERM

# Esecuzione dello script principale
main "$@"
