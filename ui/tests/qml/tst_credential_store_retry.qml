import QtQuick
import QtTest
import "../../providers" as Providers

// A mailbox restored at login can ask the credential store before the password
// manager that owns it has finished starting or the database it serves has been
// unlocked. The store says it is unavailable, which is not the same answer as
// "this mailbox has no password": the second one stays true, the first changes
// a moment later. These pin the difference — the lookup is repeated, and it is
// repeated only while the store is the thing that failed.
Item {
  id: root

  QtObject {
    id: store
    property bool available: false
    property string value: "app-password"
    property int lookups: 0
    function reset() {
      available = false
      value = "app-password"
      lookups = 0
    }
    function credentialGet(kind, accountId, clientId, callback) {
      lookups++
      if (!available) {
        callback("", "credential_store_unavailable")
        return true
      }
      callback(value, "")
      return true
    }
  }

  Component {
    id: imapFactory

    Providers.ImapAuth {
      pluginDir: "/synthetic"
      platform: store
      accountId: "imap:one@example.org"
      settings: ({imapHost:"imap.example.org",imapPort:993,smtpHost:"smtp.example.org",
        smtpPort:465,username:"one@example.org",aliases:[],insecure:false})
    }
  }

  Component {
    id: jmapFactory

    Providers.JmapAuth {
      pluginDir: "/synthetic"
      platform: store
      accountId: "jmap:one@example.org"
      address: "one@example.org"
      settings: ({sessionUrl:"https://jmap.example.org/session",username:"one@example.org",
        authScheme:"basic",accountId:"one"})
    }
  }

  TestCase {
    name: "CredentialStoreRetry"

    function init() { store.reset() }

    function test_an_unavailable_store_is_asked_again_by_an_imap_mailbox() {
      var auth = createTemporaryObject(imapFactory, root)
      verify(auth)
      auth.restoreSession()
      compare(store.lookups, 1)
      compare(auth.loggedIn, false)
      compare(auth.lastError, "The credential store is unavailable")

      // The store finishes starting, or the user unlocks it, before the
      // mailbox is looked at again.
      store.available = true
      tryVerify(function() { return auth.loggedIn }, 8000)
      verify(store.lookups >= 2)
      compare(auth.password, "app-password")
      compare(auth.secretRetryAttempt, 0)
    }

    function test_an_unavailable_store_is_asked_again_by_a_jmap_mailbox() {
      var auth = createTemporaryObject(jmapFactory, root)
      verify(auth)
      auth.restoreSession()
      compare(store.lookups, 1)
      compare(auth.loggedIn, false)
      compare(auth.lastError, "The credential store is unavailable")

      store.available = true
      tryVerify(function() { return auth.loggedIn }, 8000)
      verify(store.lookups >= 2)
      compare(auth.secret, "app-password")
      compare(auth.secretRetryAttempt, 0)
    }

    function test_a_missing_credential_is_not_asked_again() {
      store.available = true
      store.value = ""
      var auth = createTemporaryObject(imapFactory, root)
      verify(auth)
      auth.restoreSession()
      compare(store.lookups, 1)
      compare(auth.loggedIn, false)
      compare(auth.password, "")
      // No retry is scheduled: the answer will not change by itself.
      compare(auth.secretRetryAttempt, 0)
    }
  }
}
