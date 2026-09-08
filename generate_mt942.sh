#!/bin/sh
# ============================================================
# BRAC MT942 RPT Generator - Linux/macOS
# POSIX /bin/sh compatible.
# No administrator/root permission required.
# ============================================================

echo
echo "=========================================="
echo "       BRAC MT942 RPT FILE GENERATOR"
echo "=========================================="
echo

while :
do
    printf "Enter Transaction Type (D/C): "
    IFS= read -r TXN_TYPE

    case "$TXN_TYPE" in
        D|d)
            TXN_TYPE="D"
            break
            ;;
        C|c)
            TXN_TYPE="C"
            break
            ;;
        *)
            echo "Invalid input. Please type only D or C."
            ;;
    esac
done

while :
do
    printf "Enter Amount (whole number only): "
    IFS= read -r AMOUNT

    if [ -n "$AMOUNT" ] && expr "$AMOUNT" : '^[0-9][0-9]*$' >/dev/null 2>&1
    then
        break
    fi

    echo "Invalid amount. Please enter numbers only, without decimal point or letters."
done

while :
do
    printf "Enter TNX Number: "
    IFS= read -r TNX

    if [ -n "$TNX" ]
    then
        break
    fi

    echo "Invalid TNX number. Please enter a value."
done

# YYMMDDMMDD for the :61: field. Time is NOT used here.
DATESTAMP=$(date '+%y%m%d%m%d')

# YYYYMMDDHHMMSS for the output filename.
FILESTAMP=$(date '+%Y%m%d%H%M%S')

FILENAME="BRACBD02.PAYMENTS.${FILESTAMP}.1049.MT942.rpt"
OUTPUT="${PWD}/${FILENAME}"

cat > "$OUTPUT" <<EOF
{1:F01SCBLBDDXXXXX3234100042}{2:O9421232241202SCBLBDDXXXXX32341000422412021232N}{3:{108:00000000003880}}{4:
:20:24120205fr150001
:25:01600028203BDT
:28C:42/1
:34F:BDT0,
:13D:2412021232+0800
:61:${DATESTAMP}${TXN_TYPE}T${AMOUNT},00N508${TNX}//
${TNX}
:86:D02564C00004720001-${TNX}
SB9999241202FX12
DDX2262450000030
:61:2412021202DT9600,00N208NONREF          //
:86:IL99992412020012
BRAC BANK PLC
BRAKBDDHXXX
BRA2412020007469
:61:2412021202CT100000,00N208NONREF          //
:86:IL99992412020014
BRAC BANK PLC
BRAKBDDHXXX
BRA2412020007470
-}{5:{CHK:CHECKSUM DISABLED}{MAC:MACCING DISABLED}}
EOF

echo
echo "=========================================="
echo "File generated successfully:"
echo "$OUTPUT"
echo "=========================================="
echo
