#!/bin/bash

#verific daca sunt suficiente argumente
if [ "$#" -lt 2 ]; then
  echo "Usage: $0 file.xml [read|write]"
  exit 1
fi

FILE=$1
MODE=$2
TAG=$3


# functie pt citire + afisare xml content 
read_xml() {
    # extrag continutul dintre tagurile de deschidere si inchidere 
    content=$(sed -n "s:.<$TAG>\(.\)</$TAG>.*:\1:p" "$FILE")
 
    # daca tagururile sunt nested , parsez si afisez structura din interior , daca nu doar textul din interior
    if [ -z "$content" ]; then
        # sterg tag u de inchidere si refac structura tag ului de deschidere
        lines=$(sed -n "/<$TAG>/,/<\/$TAG>/p" "$FILE" | sed 's:<\/[^>]*>::g' | sed 's/<//g' | sed 's/>/: /g')
        echo "$lines" | sed "s/^$(echo "$lines" | head -n 1 | sed 's/^\( \)./\1/')//"
    else
        print_value $TAG $FILE
    fi
}
 
print_value() {
    while IFS= read -r line; do
        echo "$TAG": "$line"
    done <<< "$content"
}


# fct de testare daca exista fisierul si daca fisierul are structura xml
init_xml_if_needed() {
    local file="$1"
    local root="$2"
    
    # daca nu exista , creez fisier
    if [ ! -f "$file" ]; then
        echo "<$ROOT>" >> "$file"
    fi
}


# fct de tesatre daca exista tag ul
tag_exists() {
    local file="$1"
    local tag="$2"
    grep -q "<$tag>" "$file"
    return $?
}

#fct de update al tag ului deja existent
update_tag() {
    local file="$1"
    local tag="$2"
    local value="$3"
    local indent="$4"
    
    # creez un temporary file
    temp_file=$(mktemp)
    
    
    # update tag value 
    awk -v tag="$tag" -v value="$value" -v indent="$indent" '
        /<'$tag'>[^<]*<\/'$tag'>/ {
            print indent "<'$tag'>" value "</'$tag'>"
            next
        }
        {print}
    ' "$file" > "$temp_file"
    
    mv "$temp_file" "$file"
}


# fct pt stergerea unui tag si al continutului lui
delete_tag() {
    local file="$1"
    local tag="$2"
    
    #din nou temp file
    temp_file=$(mktemp)
    
 
    #sterge doar tag ul specificat si continutul lui
    awk -v tag="$tag" '
        BEGIN { skip=0; depth=0 }
        /<'$tag'>[^<]*<\/'$tag'>/ { next }  # Skip single-line tags
        /<'$tag'>/ { skip=1; depth=1; next }
        skip==1 && /<[^\/][^>]*>/ { depth++ }
        skip==1 && /<\/[^>]*>/ { depth-- }
        skip==1 && depth==0 { skip=0; next }
        !skip { print }
    ' "$file" > "$temp_file"
    
    mv "$temp_file" "$file"

    # sterge liniile goale si fixeaza indentarea
    temp_file=$(mktemp)
    awk '
        NF { print }
    ' "$file" > "$temp_file"
    mv "$temp_file" "$file"
}

# fct modificare children
write_children() {
    local PARENT="$1"
    local INDENT="$2"
    local PARENT_COUNT="$3"
    
    for ((i = 1; i <= PARENT_COUNT; i++)); do
        echo "Enter name for child element #$i of $PARENT (add -delete to remove tag):"
        read NAME

        #handle stergere
        if [[ "$NAME" == *-delete ]]; then
            local TAG_TO_DELETE=$(echo "$NAME" | sed 's/-delete//g' | tr -d ' ')
            if tag_exists "$FILE" "$TAG_TO_DELETE"; then
                delete_tag "$FILE" "$TAG_TO_DELETE"
                echo "Deleted tag: $TAG_TO_DELETE"
            else
                echo "Tag $TAG_TO_DELETE not found"
            fi
            continue
        fi

       
        # sterge orice nested din numeles tag ului 
        local TAG_NAME=$(echo "$NAME" | sed 's/-nested//g' | tr -d ' ')

        if [[ "$NAME" == -nested ]]; then
            if tag_exists "$FILE" "$TAG_NAME"; then
                echo "Tag $TAG_NAME already exists. Skipping..."
                continue
            fi
            echo "${INDENT}<$TAG_NAME>" >> "$FILE"
            echo "Enter the number of child elements for $TAG_NAME:"
            read CHILD_COUNT
            if [ "$CHILD_COUNT" -gt 0 ]; then
                write_children "$TAG_NAME" "${INDENT}  " "$CHILD_COUNT"
            fi
            echo "${INDENT}</$TAG_NAME>" >> "$FILE"
        else
            echo "Enter value for $TAG_NAME:"
            read VALUE
            if tag_exists "$FILE" "$TAG_NAME"; then
                update_tag "$FILE" "$TAG_NAME" "$VALUE" "$INDENT"
                echo "Updated existing tag: $TAG_NAME"
            else
                echo "${INDENT}<$TAG_NAME>$VALUE</$TAG_NAME>" >> "$FILE"
                echo "Added new tag: $TAG_NAME"
            fi
        fi
    done
}


# modifica fct write_xml
write_xml() {    
    init_xml_if_needed "$FILE" "$ROOT"
    
    echo "Enter the number of child elements to add/update:"
    read ROOT_COUNT

    if [ "$ROOT_COUNT" -gt 0 ]; then
        write_children "$ROOT" "  " "$ROOT_COUNT"
    fi
}

case $MODE in
  read)
    read_xml
    ;;
  write)

    #verifica daca fisierul are deja root element
    if [ -f "$FILE" ] && grep -q "<.>.</.*>" "$FILE"; then
        # extract existing root tag
        #EXISTING_ROOT=$(grep -o '<[^>]*>' "$FILE" | head -n 2 | tail -n 1 | sed 's/<\|>//g')
        EXISTING_ROOT=$(head -n 1 "$FILE" | sed 's/[<>]//g')
        if [ -z "$EXISTING_ROOT" ]; then
          echo "Enter the root element name (e.g., data):"
          read ROOT
        else
          ROOT="$EXISTING_ROOT"
        fi
    else
      echo "Enter the root element name (e.g., data):"
      read ROOT
    fi
    end_tag="</${ROOT}>"
    if [ -f "$FILE" ]; then
      sed -i "s|$end_tag||g" "$FILE"
    fi
    
    write_xml      
    #sterge liniile goale de diniante de root
    sed -i '/^$/d' "$FILE"
    # adauga root end 
    echo "$end_tag" >> "$FILE"
    # sterge liniile goale de dupa  root
    sed -i '/^$/d' "$FILE"
    ;;
  *)
    echo "Invalid mode: $MODE"
    echo "Usage: $0 file.xml [read|write]"
    exit 1
    ;;
esac