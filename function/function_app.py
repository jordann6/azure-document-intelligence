import json
import logging
import os
from datetime import datetime, timezone

import azure.functions as func
from azure.ai.documentintelligence import DocumentIntelligenceClient
from azure.data.tables import TableServiceClient
from azure.identity import ManagedIdentityCredential
from azure.storage.blob import BlobServiceClient

app = func.FunctionApp()


@app.blob_trigger(
    arg_name="myblob",
    path="raw/{name}",
    connection="DOC_STORAGE",
)
def process_document(myblob: func.InputStream) -> None:
    doc_name = myblob.name.split("/")[-1]
    logging.info("Processing: %s (%d bytes)", doc_name, myblob.length)

    credential = ManagedIdentityCredential()
    storage_name = os.environ["STORAGE_ACCOUNT_NAME"]
    blob_url = f"https://{storage_name}.blob.core.windows.net"
    table_url = f"https://{storage_name}.table.core.windows.net"

    di_client = DocumentIntelligenceClient(
        endpoint=os.environ["DOC_INTEL_ENDPOINT"],
        credential=credential,
    )
    poller = di_client.begin_analyze_document(
        "prebuilt-document",
        body=myblob.read(),
        content_type="application/octet-stream",
    )
    result = poller.result()

    now = datetime.now(timezone.utc).isoformat()
    extracted = {
        "document_name": doc_name,
        "analyzed_at": now,
        "model": "prebuilt-document",
        "page_count": len(result.pages) if result.pages else 0,
        "key_value_pairs": [
            {
                "key": kv.key.content if kv.key else None,
                "value": kv.value.content if kv.value else None,
                "confidence": round(kv.confidence, 4) if kv.confidence else None,
            }
            for kv in (result.key_value_pairs or [])
        ],
        "content_snippet": (result.content or "")[:500],
    }

    # Write JSON extraction result to processed container
    blob_svc = BlobServiceClient(account_url=blob_url, credential=credential)
    result_name = doc_name.rsplit(".", 1)[0] + ".json"
    blob_svc.get_container_client("processed").upload_blob(
        name=result_name,
        data=json.dumps(extracted, indent=2).encode(),
        overwrite=True,
    )

    # Write metadata row to Table Storage for fast querying
    table_svc = TableServiceClient(endpoint=table_url, credential=credential)
    table_svc.get_table_client("extractions").upsert_entity({
        "PartitionKey": "document",
        "RowKey": doc_name.replace(".", "_").replace(" ", "_"),
        "DocumentName": doc_name,
        "PageCount": extracted["page_count"],
        "KvPairCount": len(extracted["key_value_pairs"]),
        "AnalyzedAt": now,
        "ResultBlob": result_name,
        "Status": "processed",
    })

    logging.info(
        "Completed: %s — %d pages, %d key-value pairs",
        doc_name,
        extracted["page_count"],
        len(extracted["key_value_pairs"]),
    )
