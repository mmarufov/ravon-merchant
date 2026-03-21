# Ravon Merchant — Restaurant Management App

## What This Is

iOS app for restaurant owners/staff to manage incoming orders and their menu. This is a work tool — it sits on a dedicated phone or tablet at the restaurant counter. UI is in Russian.

## Tech Stack

- Swift, SwiftUI, MVVM
- Supabase (via RavonCore package)
- iOS 17+
- SPM for dependencies

## Shared Package

This app depends on `RavonCore` (github.com/mmarufov/ravon-core) which provides:
- All data models (Restaurant, MenuItem, MenuCategory, Order, OrderItem, OrderStatus, Profile, etc.)
- AuthService (sign in/up/out, session management)
- SupabaseService (database queries, order status updates)
- Theme (colors, buttons, text fields)

Import with `import RavonCore`. Call `RavonCore.configure(supabaseURL:supabaseAnonKey:)` at app launch.

## What To Build

### MVP Features (Priority Order)

1. **Auth**: Login screen for merchant accounts (role: merchant)
2. **Order Queue**: Live list of incoming orders grouped by status
   - New orders (status: created) — accept or reject
   - Accepted → Preparing → Ready flow with tap-to-advance
   - Sound/vibration alert on new orders
3. **Order Detail**: View order items, customer notes, delivery address
4. **Menu Management**: View/edit menu items, toggle availability, update prices
5. **Settings**: Restaurant info, operating hours

### Suggested Architecture
