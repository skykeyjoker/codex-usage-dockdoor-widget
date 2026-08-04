# Third-party notices

## CodexBar

The quota-source selection and CLI RPC behavior, OAuth usage field mapping,
credential refresh flow, local token-log aggregation, models.dev price refresh,
long-context/Priority/cache pricing behavior, and OpenAI status grouping were
adapted from [CodexBar](https://github.com/steipete/CodexBar), copyright 2026
Peter Steinberger, under the MIT License. The complete license text is kept in
[`CodexUsageMonitor/CODEXBAR_LICENSE.txt`](CodexUsageMonitor/CODEXBAR_LICENSE.txt).

## DockDoor Pro widget SDK

The widget imports `DockDoorWidgetSDK`, which is supplied by the
[DockDoor Pro widget repository](https://github.com/ejbills/dockdoorpro-widgets)
under its Business Source License 1.1 terms. The SDK source and build
infrastructure are not vendored in this repository; `scripts/build.sh` obtains
them from the upstream repository for the purpose of building this widget.

DockDoor Pro, Codex, ChatGPT, and OpenAI are names of their respective owners.
This project is an independent community widget and is not an official OpenAI
or DockDoor Pro product.
