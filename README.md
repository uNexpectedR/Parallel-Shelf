# Parallel Shelf

A public library that runs in [Logos Basecamp](https://github.com/logos-co/logos-basecamp). Anyone can add books and audiobooks.

It starts empty. There are no sample books in the app or in this repository. The published packages are **0.1.3** (view and core). Settings epoch stays `parallel_shelf_v1` / `1.0.0` so existing shelves are not wiped. Files live on Logos Storage. Logos Delivery tells other installs that something was added. Books stay with the people who add them.

The room has two shelves:

- **Your Shelf** (left): books you added on this install
- **Parallel Shelf** (right): books other people added

## Add it in Logos Basecamp

1. Open Basecamp. Go to **Settings → Repositories**.
2. Add this link:

   ```
   https://raw.githubusercontent.com/uNexpectedR/Parallel-Shelf/main/logos-repo.json
   ```

3. Leave the built-in repository on, so Logos Storage and Logos Delivery can install.
4. In the package manager, install **Parallel Shelf**. Accept the packages it depends on.
5. Open it from your apps. Restart Basecamp if it is not there yet.

On a Mac you need Apple Silicon (M1 or newer) and the Basecamp `.dmg`. On Linux (Intel/AMD) use the `.AppImage`. There is no Intel Mac build.

## Using it

Click **Add to the shelf**, give a title and an author, **Choose file**, then **Share**. Only add work you have the right to share. Once it is on the shelf you cannot take it back.

Click a book to read it, or an audiobook to play it. **Download** is under the book.

[Apache 2.0](LICENSE).
