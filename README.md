# Tapat AI

Tapat AI is an offline-first, on-device knowledge assistant. Imported documents, chat history, embeddings, and model files stay on the device. Network access is used only when a user downloads a model from Hugging Face.

## Local AI setup

1. Run the app and open **Settings → Local AI Models**.
2. Download or import one language model and one embedding model. The recommended catalog includes Qwen2.5 1.5B Instruct (Q4_K_M, about 986 MB, Apache-2.0) and BGE Small English v1.5 (Q4_K_M, 384 dimensions). Model size and RAM estimates are shown in the catalog; actual memory needs vary by device and context length.
3. Activate both models. Chat and ingestion stay disabled until both are loaded. After download, inference and document search work offline.

You can optionally save a Hugging Face access token in the model screen for repositories that require authentication. Model downloads support progress, pause/resume, cancellation, retry, and SHA-256 checks when a checksum is supplied by the catalog. Imported `.gguf` files are checked for GGUF magic and copied into app storage. The current inference adapter supports GGUF; ONNX imports are not enabled.

## Documents and search

Supported input formats are PDF, TXT, Markdown (`.md`), and DOCX. PDF extraction preserves page numbers. Scanned PDFs without an embedded text layer are not OCR processed; export an OCR searchable PDF before importing. Text files use UTF-8 with fallback decoding. Content is chunked with overlap, embedded in batches, and saved in the local ObjectBox database. Ingestion cancellation rolls back the partial document and chunks.

Knowledge Base search matches topic names and document names. RAG answers retrieve only chunks from the open topic and include source references to the document and page when available. If there are no matching document chunks, the assistant reports that it could not find the answer in the documents.

## NFC

NFC tags store a `tapat://kb/{topic-id}` URI and a Tapat external-type record. Scanning or writing requires an NFC-capable device with NFC enabled. Android handles the Tapat URI scheme from an NFC NDEF intent and app links. iOS requires the NFC reader permission and Core NFC entitlement configured in this project. Unsupported devices, read-only tags, and insufficient tag capacity produce an error in the app.

## Build and platform setup

Install Flutter and the platform toolchains, then run:

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

ObjectBox generated files are checked in; rerun `build_runner` after changing an entity. Android is configured for minSdk 24 and arm64-v8a. Build with `flutter build apk` or `flutter build appbundle`. For iOS, open `ios/Runner.xcworkspace` in Xcode, configure signing, ensure the Runner target embeds the `llama.xcframework` distributed by `llama_cpp_dart`, and build with `flutter build ios`. The current llama.cpp Dart package uses an isolate-owned native engine; its iOS framework embedding is a native Xcode integration step and may need to be repeated when upgrading the plugin. iOS deployment target is 15.0.

The PDF extractor is Syncfusion Flutter PDF. Review Syncfusion's current community/commercial licensing terms before distributing the app. The selected `llama_cpp_dart` release is a development prerelease; verify its platform setup instructions when upgrading or shipping a new release.

## Troubleshooting

- **Chat or upload asks for models:** activate both a language model and a 384-dimensional embedding model in Local AI Models.
- **Model fails to load:** check free storage/RAM, confirm the model is a supported GGUF file, and try a smaller quantization. Models imported as ONNX are not currently supported by the inference adapter.
- **Embedding dimension mismatch:** this database uses 384-dimensional cosine vectors. Activate a compatible embedding model, then use Re-index in Local AI Models to regenerate document vectors.
- **A PDF imports with no text:** it is likely scanned or image-only. OCR it externally and import a searchable PDF.
- **NFC is unavailable:** enable NFC in system settings and confirm the device has an NFC reader. iOS may require the correctly signed Runner target with the NFC entitlement.
- **Storage is full:** remove unused models, clear the model download cache, or export a backup before deleting data.

## Tests

Run the unit and widget test suite with:

```sh
flutter test
```
