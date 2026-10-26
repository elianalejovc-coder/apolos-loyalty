# Apolo's Loyalty — Product Specification

## Product goal
Create a QR-accessible digital loyalty coupon for Apolo's. Ten staff-confirmed visits earn a reward. Customers should be able to check progress on a phone without installing an app.

## Interfaces

### 1. Customer mobile experience
- Opened by scanning a restaurant QR code.
- Show the Apolo's brand, loyalty progress (0–10), stamps earned, remaining visits, and available/redeemed rewards.
- Explain the reward and the rules clearly.
- Provide a low-friction way to link a verified phone or email for recovery.
- Customers may update allowed profile/recovery fields only; never stamps, visits, reward issuance, or redemption state.
- The public landing/QR route does not itself register a visit.
- If the customer has no recovery method and changes devices, do not promise cross-device recovery. Explain the limitation and offer a verified recovery method.

### 2. Staff/admin console
- Protected sign-in.
- Dashboard: visit activity, customers, rewards awaiting redemption, and recent actions.
- Find/create a customer with a privacy-conscious flow.
- Register a valid visit only after staff confirms the visit.
- Search customer and view loyalty progress.
- Redeem a reward by validating its unique code/QR.
- Admin-only management of staff roles, reward rules, and settings.
- Audit log for sensitive actions.
- Employee role can register visits and redeem rewards; admin role can also manage settings and staff.

## Loyalty rules
- Default threshold: 10 valid visits per reward.
- A visit is counted only after a staff-authenticated server operation.
- Define and enforce the duplicate policy (recommended: one stamp per customer per qualifying visit/event, with a unique idempotency key).
- The threshold and reward description should be configurable by an admin, with changes recorded in the audit log.
- Issuing a reward must be atomic with the qualifying visit to prevent race conditions.
- Redemption is one-time only and must be atomic.
- Failed/replayed operations must not add stamps or redeem rewards twice.

## Design direction
- Navy #101A2B, gold #D6B36A, ivory #F6F0E4, white.
- Success #287D5A; alert #B83D45.
- Suggested type: Cormorant Garamond headings, Inter interface.
- Premium, contemporary, restrained Hellenic visual language; subtle Apollo sun/laurel motifs.
- Large touch targets, clear progress visualization, responsive layout, readable contrast, keyboard accessibility.

## Privacy and security
- Do not rely on device fingerprinting.
- Collect only data needed for loyalty and account recovery.
- Never expose other customers' records.
- Never put service-role credentials in the client.
- All privileged mutations must be checked server-side and leave an audit trail.
- Establish retention, privacy notice, consent language, and support/recovery procedure before launch.

## Out of scope for initial MVP
- Native iOS/Android app.
- Payments, POS integrations, marketing automation, WhatsApp messaging, or multi-branch analytics unless explicitly added later.
- Public self-awarding stamps or client-controlled reward status.

## Acceptance criteria
1. Scanning QR opens the customer page and does not alter the balance.
2. A customer can only view their own loyalty data.
3. A staff member can record a qualifying visit; unauthorized users cannot.
4. Repeated requests with the same idempotency key do not create duplicate visits.
5. At the tenth valid visit, exactly one reward is issued according to the active rule.
6. A reward can be redeemed once; replay attempts are rejected.
7. Staff actions are auditable.
8. Recovery is possible through a verified linked method; no device fingerprinting is used.
