from diagrams import Diagram, Cluster, Edge
from diagrams.azure.compute import FunctionApps
from diagrams.azure.storage import BlobStorage, TableStorage
from diagrams.azure.identity import ManagedIdentities
from diagrams.azure.aimachinelearning import FormRecognizers

graph_attrs = {
    "fontsize": "13",
    "bgcolor": "white",
    "pad": "0.5",
    "splines": "ortho",
}

node_attrs = {
    "fontsize": "11",
}

with Diagram(
    "Azure Serverless Document Intelligence",
    filename="docs/architecture",
    outformat="png",
    show=False,
    direction="LR",
    graph_attr=graph_attrs,
    node_attr=node_attrs,
):
    with Cluster("rg-docintel-dev · East US"):
        func = FunctionApps("Azure Function\nBlob Trigger · Python 3.11\nConsumption Plan")
        identity = ManagedIdentities("Managed Identity\n(System Assigned)\n6 RBAC role assignments")
        doc_intel = FormRecognizers("Document Intelligence\nprebuilt-document model")

        with Cluster("Storage Account · stdocsdev{suffix}"):
            raw = BlobStorage("raw/\nInput Container")
            processed = BlobStorage("processed/\nJSON Extraction Results")
            table = TableStorage("extractions\nMetadata Index")

    raw >> Edge(label="blob trigger") >> func
    func >> Edge(label="authenticates via") >> identity
    identity >> Edge(label="RBAC: Cognitive Services User") >> doc_intel
    doc_intel >> Edge(label="key-value pairs + content") >> func
    func >> Edge(label="upload JSON result") >> processed
    func >> Edge(label="upsert metadata row") >> table
