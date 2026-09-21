---
title: Privacy Policy
permalink: /privacy/
---
# Privacy Policy — Ironyx

**Last updated: September 21, 2026**

Ironyx ("the app") is an offline-first workout and fitness log. This policy
explains what data the app collects, where it goes, how it is used, and what
choices you have. Ironyx is not a medical device and is not a substitute for
professional medical advice, diagnosis, or treatment. If anything here is
unclear, contact mustafa.salih15@gmail.com.

## The short version

- You can use Ironyx completely without an account. In that mode, nothing
  you enter ever leaves your device.
- Creating an account is optional and exists only to enable an opt-in
  cloud backup feature. It does not unlock any other functionality.
- We do not run ads, analytics, or trackers of any kind. We do not sell your
  data. The only service provider that receives data from Ironyx is Supabase,
  and only when you use the account or optional cloud-backup features.

## Data stored only on your device

Whether or not you create an account, the following stays in a local
database on your device and is never transmitted anywhere unless you
explicitly use the cloud backup feature described below:

- Workouts, exercises, sets, reps, and weights you log
- Training programs and templates you create or import
- Body and fitness metrics you choose to enter (e.g. body weight, height,
  date of birth, sex, workouts, sets, reps, weights, and rest times) — used
  only to provide the app's logging, charts, and program features
- Profile details you choose to enter, such as display name and weekly
  session target
- App settings (units, sound, haptics, language)

Ironyx does not connect to Google Fit, Health Connect, Apple Health, or other
health platforms, and it does not collect location, heart rate, steps, or
other sensor data.

Uninstalling the app deletes this data permanently. There is no server
copy unless you have used cloud backup (below). You can also export your
data to a file at any time from Settings, and delete all local data from
Settings without uninstalling.

On Android, Ironyx opts out of the operating system's automatic app backup
to Google Drive, so neither your local database nor your sign-in session is
copied there by Android. Use the export file or the optional cloud backup
if you want a copy that survives a reinstall.

## If you create an account

Account creation is handled by Supabase, our backend provider, and
requires only an email address and password. We use this solely to:

- Authenticate you (sign you in)
- Associate an optional cloud backup with your identity

An account by itself does not upload your workout data. Your email
address is stored by Supabase to operate the login system and is not
used for marketing, shared with advertisers, or sold. The only emails
sent to that address are ones you trigger: the confirmation message when
you sign up and the link when you ask to reset your password. Those
messages are delivered through an email-sending service that acts on our
behalf; it handles your email address only to deliver them and does not use
it for any other purpose.

## Cloud backup (optional, opt-in, off by default)

If you are signed in and tap "Back up now" in Settings, the app uploads a
compressed copy of your entire local database to Supabase's servers,
associated with your account. This is:

- **Never automatic.** It only happens when you tap the button.
- **One slot per account.** A new backup replaces the previous one.
- **Restorable** on any device by signing in and tapping "Restore from my
  account," which replaces the data on that device.

Data in transit is encrypted using HTTPS/TLS. The cloud backup is retained
until you overwrite it with a newer backup, request its deletion, or delete
your account. To request deletion of your cloud backup, account, or any other
personal data held by Supabase, contact us at the address above. Account
records and the backup associated with an account are deleted when we process
the request; Supabase's service infrastructure may retain limited records for
security, fraud prevention, backups, or legal compliance for the period
required for those purposes.

## Permissions the app requests, and why

- **Internet** — only used for sign-in and the optional cloud backup
  described above. The app functions fully offline without it.
- **Notifications** — to alert you when a timer phase changes or a rest
  timer finishes while the app is in the background.
- **Vibrate** — for haptic feedback on timers and set completion.
- **Wake lock** — to keep the screen on during an active workout so a
  timer doesn't get interrupted.
- **Receive boot completed** — to re-schedule a pending rest-timer
  notification if your phone restarts mid-workout.
- **Exact alarms** — so a timer phase-change notification arrives at the
  moment the phase changes rather than being delayed by the system. It is
  used only for the timers you start.

The app does not request location, camera, microphone, contacts, or any
other permission not listed here.

## Analytics, advertising, and third parties

Ironyx contains no analytics SDK, no advertising SDK, and no crash-reporting
service. The only third-party service the app talks to is Supabase. Supabase
provides email/password authentication and stores the optional cloud backup
when you explicitly use that feature. Supabase may process this information
as our service provider under its own terms and privacy policy. Supabase
sends the sign-up and password-reset emails through the email-sending service
described above. Ironyx does not sell data or use it for advertising or
behavioral tracking.

## Data deletion and your choices

- **Local data:** Settings → Data Management → Delete everything. You can
  also uninstall Ironyx or export your data before deleting it. Local data is
  not recoverable after deletion unless you previously made a cloud backup or
  export.
- **Account and cloud backup:** If you use an account, Settings → Account →
  Delete account permanently removes your Supabase account and associated
  cloud backup. You must type `DELETE` to confirm. Workouts and other data
  stored locally on this device remain until you separately remove them from
  Settings → Data Management. If you cannot use the in-app option, email
  mustafa.salih15@gmail.com to request deletion of your Supabase account,
  email address, cloud backup, and other personal data held for your account.
  We may ask you to verify ownership before processing the request.
- **Email address:** You can stop using the account at any time. We do not
  use it for marketing.

## Children's privacy

Ironyx is not directed at children under 13, and we do not knowingly collect
data from children under 13. If you believe a child has provided personal
data, contact us so we can investigate and delete it where appropriate.

## Changes to this policy

If this policy changes, the "Last updated" date above will change and,
for any material change, we will note it in the app's release notes.

## Contact

mustafa.salih15@gmail.com
