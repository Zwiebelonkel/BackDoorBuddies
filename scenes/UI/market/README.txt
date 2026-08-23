BACKDOOR BROS - DARKNET MARKET TERMINAL

PRODUCTION FLOW
1. Player opens the mesh terminal in the van with E.
2. The SubViewport receives mouse and keyboard input from the 3D screen.
3. Player selects one exact inventory-item instance and publishes a price.
4. The server owns listings, timers, offers, reservations and wallets.
5. ACCEPT changes the listing to DELIVERY_REQUIRED. It does not pay yet.
6. The exact reserved item is selected and must be dropped with G into the
   glowing SALE DROP area below the terminal.
7. The server atomically claims that pickup, marks the listing SOLD and pays
   the seller exactly once.

PRODUCTION FILES
- darknet_market_terminal.tscn     SubViewport UI used by the van
- darknet_market_v2.gd             UI controller and server request client
- darknet_listing_row.gd           Listing/status row
- ../../props/van/DarknetTerminal.tscn
- ../../../scripts/darknet_market_manager.gd

The original darknet_market_v2.tscn is kept as the imported design draft.
DarknetTerminal.tscn intentionally instances darknet_market_terminal.tscn.

MULTIPLAYER AUTHORITY
- Clients only request actions.
- The server verifies terminal proximity and inventory ownership.
- Item instance IDs survive pickup, inventory, drop and death-drop round trips.
- A wrong item, an already claimed pickup or a repeated delivery cannot pay.
- Late clients request a fresh market snapshot until synchronized.

TERMINAL CONTROLS
- E: open/close terminal
- Escape: close terminal before opening the options menu
- Mouse: click the UI directly on the mesh
- G after leaving the terminal: drop the selected sold item into SALE DROP
