#!/bin/bash

# Configurazione
OPENAI_API_KEY="${OPENAI_API_KEY}"
TOPICS_FILE="topics.txt"
DOCS_DIR="docs/posts"
TEMP_FILE="/tmp/openai_response.json"
PROCESSED_TOPICS="processed_topics.txt"

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funzione per logging
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Verifica prerequisiti
check_requirements() {
    log "Verifica prerequisiti..."

    if [ -z "$OPENAI_API_KEY" ]; then
        error "OPENAI_API_KEY non impostata. Esporta la chiave API:"
        error "export OPENAI_API_KEY='your-api-key-here'"
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
        error "curl non installato"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        error "jq non installato. Installa con: sudo apt-get install jq"
        exit 1
    fi

    # Crea directory se non esistono
    mkdir -p "$DOCS_DIR"

    # Crea file topics.txt se non esiste
    if [ ! -f "$TOPICS_FILE" ]; then
        warning "File $TOPICS_FILE non trovato. Creando file di esempio..."
        cat > "$TOPICS_FILE" << 'EOF'
API Design Best Practices
Microservices Architecture
Container Orchestration
CI/CD Pipeline Optimization
Code Review Strategies
Testing Automation
Documentation Standards
Performance Monitoring
Security Best Practices
Developer Tooling
EOF
        log "File $TOPICS_FILE creato con argomenti di esempio"
    fi

    # Crea file processed_topics.txt se non esiste
    if [ ! -f "$PROCESSED_TOPICS" ]; then
        touch "$PROCESSED_TOPICS"
        log "File $PROCESSED_TOPICS creato"
    fi
}

# Leggi argomenti non ancora processati
get_unprocessed_topics() {
    local available_topics=()

    while IFS= read -r line; do
        if [ -n "$line" ] && ! grep -Fxq "$line" "$PROCESSED_TOPICS" 2>/dev/null; then
            available_topics+=("$line")
        fi
    done < "$TOPICS_FILE"

    printf '%s\n' "${available_topics[@]}"
}

# Seleziona argomenti da processare
select_topics() {
    local num_topics=${1:-3}
    local unprocessed_topics=($(get_unprocessed_topics))

    if [ ${#unprocessed_topics[@]} -eq 0 ]; then
        warning "Nessun argomento nuovo da processare"
        return 1
    fi

    log "Argomenti disponibili: ${#unprocessed_topics[@]}"

    # Seleziona fino a $num_topics argomenti
    local selected_topics=()
    local max_topics=$((${#unprocessed_topics[@]} < num_topics ? ${#unprocessed_topics[@]} : num_topics))

    for ((i=0; i<max_topics; i++)); do
        selected_topics+=("${unprocessed_topics[i]}")
    done

    printf '%s\n' "${selected_topics[@]}"
}

# Crea prompt per OpenAI
create_prompt() {
    local topics="$1"
    cat << EOF
Sei un esperto di Developer Experience. Per ogni argomento nella lista seguente, genera:

1. Un titolo accattivante e professionale per un post sul blog
2. 3-5 nuovi argomenti correlati che approfondiscono il tema originale

Argomenti da elaborare:
$topics

Restituisci la risposta in formato JSON strutturato così:
{
  "posts": [
    {
      "original_topic": "argomento originale",
      "title": "Titolo del post generato",
      "date": "$(date '+%Y-%m-%d')",
      "related_topics": ["nuovo argomento 1", "nuovo argomento 2", "nuovo argomento 3"]
    }
  ]
}

Assicurati che:
- I titoli siano professionali e accattivanti
- I nuovi argomenti siano specifici e approfondiscano il tema originale
- La risposta sia in JSON valido
- Tutti i contenuti siano in italiano
EOF
}

# Chiamata API OpenAI
call_openai_api() {
    local prompt="$1"

    log "Chiamata API OpenAI in corso..."

    local response=$(curl -s -X POST \
        "https://api.openai.com/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -d "{
            \"model\": \"gpt-3.5-turbo\",
            \"messages\": [{
                \"role\": \"user\",
                \"content\": $(echo "$prompt" | jq -Rs .)
            }],
            \"temperature\": 0.7,
            \"max_tokens\": 2000
        }")

    # Verifica errori API
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        error "Errore API OpenAI: $(echo "$response" | jq -r '.error.message')"
        return 1
    fi

    # Estrai contenuto della risposta
    echo "$response" | jq -r '.choices[0].message.content'
}

# Crea file post
create_post_file() {
    local title="$1"
    local date="$2"
    local original_topic="$3"

    # Crea nome file safe
    local filename=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
    local filepath="$DOCS_DIR/${date}-${filename}.md"

    # Crea contenuto post
    cat > "$filepath" << EOF
---
title: "$title"
date: $date
topic: "$original_topic"
draft: true
---

# $title

<!-- Contenuto del post da sviluppare -->

EOF

    log "Creato post: $filepath"
    echo "$filepath"
}

# Aggiorna file topics con nuovi argomenti
update_topics_file() {
    local new_topics="$1"

    # Aggiungi nuovi argomenti al file topics.txt
    echo "$new_topics" >> "$TOPICS_FILE"

    # Rimuovi duplicati mantenendo l'ordine
    awk '!seen[$0]++' "$TOPICS_FILE" > "${TOPICS_FILE}.tmp" && mv "${TOPICS_FILE}.tmp" "$TOPICS_FILE"

    log "File $TOPICS_FILE aggiornato con nuovi argomenti"
}

# Aggiorna file argomenti processati
update_processed_topics() {
    local processed="$1"
    echo "$processed" >> "$PROCESSED_TOPICS"
    log "Argomenti processati aggiunti a $PROCESSED_TOPICS"
}

# Funzione principale
main() {
    local num_topics=${1:-3}

    log "Avvio generazione post Developer Experience"
    log "Numero argomenti da processare: $num_topics"

    # Verifica prerequisiti
    check_requirements

    # Seleziona argomenti da processare
    local selected_topics=$(select_topics "$num_topics")

    if [ -z "$selected_topics" ]; then
        warning "Nessun argomento da processare"
        exit 0
    fi

    log "Argomenti selezionati:"
    echo "$selected_topics" | while read -r topic; do
        echo -e "${BLUE}  - $topic${NC}"
    done

    # Crea prompt
    local prompt=$(create_prompt "$selected_topics")

    # Chiamata API
    local api_response=$(call_openai_api "$prompt")

    if [ $? -ne 0 ]; then
        error "Chiamata API fallita"
        exit 1
    fi

    # Salva risposta temporanea
    echo "$api_response" > "$TEMP_FILE"

    # Verifica che la risposta sia JSON valido
    if ! jq empty "$TEMP_FILE" 2>/dev/null; then
        error "Risposta API non è JSON valido"
        error "Risposta: $api_response"
        exit 1
    fi

    # Processa risposta
    log "Processamento risposta API..."

    local posts_created=0
    local new_topics_list=""
    local processed_topics_list=""

    # Processa ogni post
    jq -r '.posts[] | @base64' "$TEMP_FILE" | while read -r post_data; do
        local post_json=$(echo "$post_data" | base64 --decode)

        local original_topic=$(echo "$post_json" | jq -r '.original_topic')
        local title=$(echo "$post_json" | jq -r '.title')
        local date=$(echo "$post_json" | jq -r '.date')

        # Crea file post
        create_post_file "$title" "$date" "$original_topic"

        # Raccogli nuovi argomenti
        local related_topics=$(echo "$post_json" | jq -r '.related_topics[]')
        new_topics_list="$new_topics_list$related_topics"$'\n'

        # Aggiungi agli argomenti processati
        processed_topics_list="$processed_topics_list$original_topic"$'\n'

        posts_created=$((posts_created + 1))
    done

    # Aggiorna file topics
    if [ -n "$new_topics_list" ]; then
        update_topics_file "$new_topics_list"
    fi

    # Aggiorna argomenti processati
    if [ -n "$processed_topics_list" ]; then
        update_processed_topics "$processed_topics_list"
    fi

    # Cleanup
    rm -f "$TEMP_FILE"

    log "Generazione completata!"
    log "Post creati: $posts_created"
    log "Nuovi argomenti aggiunti al pool"

    # Mostra statistiche
    local total_topics=$(wc -l < "$TOPICS_FILE")
    local processed_count=$(wc -l < "$PROCESSED_TOPICS")
    local remaining=$((total_topics - processed_count))

    echo -e "${BLUE}Statistiche:${NC}"
    echo -e "  Argomenti totali: $total_topics"
    echo -e "  Argomenti processati: $processed_count"
    echo -e "  Argomenti rimanenti: $remaining"
}

# Gestione parametri
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Uso: $0 [numero_argomenti]"
    echo ""
    echo "Genera post per blog su temi Developer Experience"
    echo ""
    echo "Parametri:"
    echo "  numero_argomenti  Numero di argomenti da processare (default: 3)"
    echo ""
    echo "Prerequisiti:"
    echo "  - export OPENAI_API_KEY='your-api-key'"
    echo "  - jq installato"
    echo "  - curl installato"
    echo ""
    echo "File necessari:"
    echo "  - topics.txt (creato automaticamente se non esiste)"
    exit 0
fi

# Esegui script
main "$@"