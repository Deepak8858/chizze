# Chizze App Flows

This document outlines the complete user journeys and flows within the Chizze application, covering all three user roles: Customer, Restaurant Partner, and Delivery Partner.

## 1. App Launch & Authentication Flow

1. **Splash Screen**: The app initializes, checks Firebase, local cache (Hive), and the current Authentication State.
2. **Role Selection**: If the user is not authenticated, they are prompted to select their intended role:
   - **Customer**: Order Food
   - **Restaurant Partner**: Manage restaurant & menu
   - **Delivery Partner**: Deliver food
3. **Login**: The user enters their phone number.
4. **OTP Verification**: The user enters the OTP sent to their phone to verify their identity.
5. **Onboarding (New Users Only)**:
   - **Customer**: Enters Name, Email, and Address (with auto-detect location feature).
   - **Restaurant Partner**: Enters Name, Email, Restaurant Name, Restaurant Address, and selects Cuisine Type.
   - **Delivery Partner**: Enters Name, Email, selects Vehicle Type (Bike, Scooter, Car, etc.), and enters Vehicle Number.
6. **Redirection**: Based on the selected role and onboarding status, the user is redirected to their respective dashboard.

---

## 2. Customer Flow

### 2.1 Main Navigation (Bottom Tab Bar)
- **Home**: Discover restaurants, view categories, promo banners, personalized offers, and top picks.
- **Search**: Search for specific restaurants, cuisines, or dishes.
- **Favorites**: View a curated list of favorite restaurants.
- **Orders**: View active (ongoing) and past orders.
- **Profile**: Access account settings, addresses, and premium features.

### 2.2 Ordering Flow
1. **Restaurant Selection**: The user taps on a restaurant from the Home, Search, or Favorites screen.
2. **Restaurant Detail**: The user views the restaurant's menu, categorized items, and general information.
3. **Add to Cart**: The user selects items, customizes them with add-ons or variants (if applicable), and adds them to their cart.
4. **Cart Review**: The user navigates to the Cart screen to review the order, apply coupons, add delivery instructions (e.g., "Leave at door"), add a tip for the delivery partner, and verify the delivery address.
5. **Payment**: The user proceeds to checkout, selects a payment method (e.g., Razorpay integration), and completes the transaction.
6. **Order Confirmation**: The user sees a success screen displaying the Order ID.
7. **Order Tracking**: The user tracks the order status in real-time (Pending -> Accepted -> Preparing -> Ready -> Out for Delivery -> Delivered) and views the delivery partner's live location on a map in realtime. The user can also call or chat with the delivery partner or restaurant.
8. **Review**: After successful delivery, the user can rate and review both the restaurant and the delivery partner.

### 2.3 Profile & Settings Flow
- **Manage Addresses**: Add, edit, or delete saved delivery addresses.
- **Notifications**: View order updates, alerts, and promotional messages.
- **Coupons**: View available discount codes and offers.
- **Referral**: Share a unique referral code with friends and view earned rewards.
- **Chizze Gold**: Subscribe to the premium membership for exclusive perks (e.g., free delivery, extra discounts).
- **Scheduled Orders**: View and manage orders that have been scheduled for a later date/time.

---

## 3. Restaurant Partner Flow

### 3.1 Main Navigation (Bottom Tab Bar)
- **Dashboard**: View daily metrics (earnings, total orders), real-time connection status, and quick actions. Toggle Online/Offline status.
- **Orders**: Manage the active order queue and view order history.
- **Menu**: Manage the restaurant's menu items and categories.
- **Analytics**: View detailed performance metrics, sales trends, and popular items.

### 3.2 Order Management Flow
1. **New Order Alert**: The partner receives a real-time notification and visual alert for a new incoming order.
2. **Accept/Reject**: The partner reviews the order details (items, special instructions) and chooses to accept or reject it.
3. **Update Status (Preparing)**: Once accepted, the partner updates the order status to "Preparing" when they start cooking.
4. **Ready for Pickup**: Once the food is prepared and packaged, the partner marks the order as "Ready", which notifies the assigned delivery partner to pick it up.

### 3.3 Menu Management Flow
1. **View Menu**: The partner sees a list of all current menu items organized by category.
2. **Add/Edit Item**: The partner can add a new dish or edit an existing one. Fields include Name, Description, Price, Image Upload (from gallery or camera), Category, Veg/Non-Veg tag, Add-ons/Variants (e.g., extra cheese, size options), and Availability toggle (In Stock / Out of Stock).
3. **Manage Categories**: The partner can create, edit, or delete menu categories to organize their offerings.

### 3.4 Profile & Settings Flow
1. **Restaurant Profile**: The partner can update their restaurant's banner image, logo, contact information, and operating hours.
2. **Payouts & Bank Details**: The partner can manage their bank account details for receiving payouts and view their payout history.
3. **Support & Help**: The partner can contact Chizze support for issues related to orders, payouts, or app functionality.

---

## 4. Delivery Partner Flow

### 4.1 Main Navigation (Bottom Tab Bar)
- **Dashboard**: Toggle Online/Offline status, view daily metrics, track weekly goals, and monitor incoming delivery requests.
- **Active Delivery**: Manage the current, ongoing delivery task with step-by-step navigation.
- **Earnings**: View earnings history, daily/weekly breakdowns, and payout status.
- **Profile**: Manage personal information and vehicle details.

### 4.2 Delivery Flow
1. **Go Online**: The partner toggles their status to "Online" on the dashboard to start receiving delivery requests.
2. **Incoming Request**: The partner receives a delivery request showing the restaurant location, customer location, estimated distance, and estimated earnings.
3. **Accept/Reject**: The partner has a limited time window to accept or reject the delivery request.
4. **Navigate to Restaurant**: Upon accepting, the partner uses the integrated map to navigate to the restaurant.
5. **Pick Up Order**: The partner arrives at the restaurant, verifies the order details/ID, and marks the order as "Picked Up" in the app.
6. **Navigate to Customer**: The partner uses the map to navigate to the customer's delivery address. The partner can call or chat with the customer if needed.
7. **Deliver Order**: The partner arrives at the customer's location, hands over the food, and marks the order as "Delivered". This may require a delivery OTP or a photo as proof of delivery.
8. **Earnings Updated**: The delivery fee and any applicable tips are immediately added to the partner's earnings dashboard.

### 4.3 Profile & Settings Flow
1. **Vehicle & Documents**: The partner can manage their vehicle details, driving license, and other KYC documents.
2. **Payouts & Bank Details**: The partner can manage their bank account details for receiving payouts and view their payout history.
3. **Support & Help**: The partner can contact Chizze support for issues related to deliveries, payouts, or app functionality.
