#!/usr/bin/env bash
set -euo pipefail

STORAGE_ACCOUNT="${1:?Usage: seed_documents.sh <storage-account-name>}"

SAMPLE_FILE=$(mktemp /tmp/sample_invoice_XXXX.txt)
cat > "$SAMPLE_FILE" <<'EOF'
INVOICE

Invoice Number: INV-2024-0042
Date: 2024-06-01
Due Date: 2024-06-15

Bill To:
  Acme Corporation
  123 Main Street
  New York, NY 10001

Item                Qty   Unit Price   Total
-------------------------------------------------
Cloud Services       1     $500.00     $500.00
Support Plan         1     $150.00     $150.00
Storage (500 GB)     1      $25.00      $25.00
-------------------------------------------------
Subtotal                               $675.00
Tax (8%)                                $54.00
Total Due                              $729.00

Payment Terms: Net 15
EOF

echo "==> Uploading sample invoice to raw container..."
az storage blob upload \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name raw \
  --name "$(basename "$SAMPLE_FILE")" \
  --file "$SAMPLE_FILE" \
  --auth-mode login

echo "Upload complete. The blob trigger will process the document within ~30 seconds."
echo ""
echo "==> Checking processed container (wait ~30s after upload)..."
sleep 30
az storage blob list \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name processed \
  --auth-mode login \
  --output table

echo ""
echo "==> Querying extractions table..."
az storage entity query \
  --account-name "$STORAGE_ACCOUNT" \
  --table-name extractions \
  --auth-mode login \
  --output table

rm "$SAMPLE_FILE"
