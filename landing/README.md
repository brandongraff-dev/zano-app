# ZANO landing page

Static waitlist page for Phase 0 (docs/spec.md §22: "landing page + waitlist" before code is
done). Plain HTML/CSS, no build step, no framework — `index.html` + `style.css`. The only
JavaScript is the inline module at the bottom of `index.html` that submits the waitlist form
straight to Supabase with the anon key (see `backend/supabase/migrations/0003_waitlist.sql` for
why that's safe: RLS restricts `anon` to insert-only on `waitlist_signups`).

## 1. Wire up a real Supabase project

As of this writing, `docs/PROGRESS.md` tracks the Supabase project itself as **not yet created** —
everything under `backend/supabase/` is local migration scaffolding until Session 7 stands up a
real hosted project. Once that project exists:

1. Apply the migrations (from `backend/`, with the Supabase CLI): `supabase db push` (hosted) or
   `supabase db reset` (local dev). This creates the `waitlist_signups` table from
   `migrations/0003_waitlist.sql` along with everything in `0001_init.sql` / `0002_auth_storage.sql`.
2. In the Supabase dashboard, grab **Project URL** and the **anon / public key**
   (Project Settings → API). Do **not** use the `service_role` key here — it bypasses RLS and must
   never ship in client-side code.
3. Open `landing/index.html` and find the two constants near the bottom of the file:

   ```js
   const SUPABASE_URL = "REPLACE_WITH_SUPABASE_PROJECT_URL"; // e.g. https://xxxxxxxx.supabase.co
   const SUPABASE_ANON_KEY = "REPLACE_WITH_SUPABASE_ANON_KEY";
   ```

   Replace both placeholders with the real values. That's it — no env vars, no build step, the
   anon key is meant to be public (RLS is what keeps it safe; see the comment above those
   constants and the comments in `0003_waitlist.sql`).
4. Until those constants are filled in, the form fails safely: it shows the visitor "Waitlist
   isn't live yet" and logs a clear message to the browser console instead of throwing.

## 2. Run it locally

It's a static page, but the Supabase submission uses a native `<script type="module">` import,
and browsers block ES module imports from a bare `file://` URL. Serve the folder instead of
double-clicking `index.html`:

```sh
cd landing
python -m http.server 8000     # or: npx serve .
```

Then open `http://localhost:8000`.

## 3. Reading signups back

The anon key can only insert rows (see `0003_waitlist.sql`). To read the list, use the
`service_role` key or the Supabase Studio/dashboard table editor — never expose `service_role` in
`index.html` or anywhere else client-side.

## 4. Deploying as a static site

No build step means any static host works — pick one, point it at this `landing/` folder, done.
Options (not deployed as part of this change, just noting them):

- **Netlify** — drag-and-drop the folder in the dashboard, or `netlify deploy` from the CLI. Set
  the publish directory to `landing/`.
- **Vercel** — `vercel` from inside `landing/`, or import the repo in the dashboard and set the
  root directory to `landing/`. No framework preset needed ("Other").
- **GitHub Pages** — enable Pages on the repo, either serving `landing/` directly (via a
  `docs/`-style path rule or a small workflow that copies it) or from a dedicated branch. Simplest
  if this page ever gets its own repo.

Whichever host is picked, point the domain/subdomain (e.g. `zano.app` or `waitlist.zano.app`) at
it and update any links in the bio/content-plan posts (docs/spec.md §22) to match.
