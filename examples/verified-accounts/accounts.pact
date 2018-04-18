;; accounts module, admin keyset, and table
; (load "examples/verified-accounts/accounts.repl")

(enforce-pact-version "2.3")

(define-keyset 'accounts-admin-keyset
  (read-keyset "accounts-admin-keyset"))

(module accounts 'accounts-admin-keyset
  "Accounts module demonstrating row-level keysets, private pacts, and escrow. \
\  Version: 0.2                                                                \
\  Author: Stuart Popejoy"

  (defschema account
    "Row type for accounts table."
     balance:decimal
     amount:decimal
     ccy:string
     auth:string     ;; AUTH_KEYSET for keysets, pact id for pacts
     data
     )

  (deftable accounts:{account}
    "Main table for accounts module.")

  (defconst AUTH_KEYSET 'K
    "Indicates keyset-governed account")

  (defconst ADMIN_KEYSET (read-keyset "accounts-admin-keyset"))


  (defun create-account (address ccy date)
    (insert accounts address
      { "balance": 0.0
      , "amount": 0.0
      , "ccy": ccy
      , "auth": AUTH_KEYSET
      , "date": date
      , "data": "Created account"
      }
    ))

  ; TODO: defproperty?
  ; (property-of transfer conserves-mass)
  (defun transfer (src dest amount date)
    "transfer AMOUNT from SRC to DEST"
    (debit src amount date { "transfer-to": dest })
    (credit dest amount date { "transfer-from": src }))

  (defun read-account-user (id)
    "Read data for account ID"
    (with-read accounts id
              { "balance":= b
              , "ccy":= c
              , "auth" := auth }
      { "balance": b, "ccy": c }
      ))

  (property (valid (not abort)))
  (defun test:bool (x:integer)
    (if (< x 10) true false))

  (property-of read-account-admin
    (valid
      (assuming
          (not (ks-name-authorized 'accounts-admin-keyset))
          abort)))
  (defun read-account-admin (id)
    "Read data for account ID, admin version"
    (enforce-keyset 'accounts-admin-keyset)
    (read accounts id ['balance 'ccy 'data 'date 'amount]))

  (defun account-keys ()
    "Get all account keys"
    (enforce-keyset 'accounts-admin-keyset)
    (keys accounts))

  (defun check-balance (balance amount)
    (enforce (<= amount balance) "Insufficient funds"))

  (defun fund-account (address amount date)
    (enforce-keyset 'accounts-admin-keyset)
    (update accounts address
            { "balance": amount
            , "amount": amount
            , "date": date
            , "data": "Admin account funding" }
      ))

  (defun read-all ()
    (map (read-account-admin) (keys accounts)))

  (defpact payment (payer payer-entity payee payee-entity amount date)
    "Debit PAYER at PAYER-ENTITY then credit PAYEE at PAYEE-ENTITY for AMOUNT on DATE"
    (step-with-rollback payer-entity
      (debit payer amount date
            { "payee": payee
            , "payee-entity": payee-entity
            ; TODO: can pact-analyze handle PACT_REF gracefully?
            , PACT_REF: (pact-id)
            })
      (credit payer amount date
           { PACT_REF: (pact-id), "note": "rollback" }))

    (step payee-entity
      (credit payee amount date
            { "payer": payer
            , "payer-entity": payer-entity
            , PACT_REF: (pact-id)
            }
      )))


  ; (property-of enforce-auth
  ;   (assuming
  ;     (not (admin current-user))
  ;     (not transaction-succeeds)))
  (defun enforce-auth (keyset:keyset auth)
    (if (= auth AUTH_KEYSET)
      (enforce-keyset keyset)
      (enforce (= auth (format "%s" [(pact-id)]))
        "Invalid access of pact account")))


  ; (property-of debit
  ;   (let
  ;     (with-read 'initial accounts acct
  ;       { "balance" := initial-balance
  ;       , "keyset" := ks
  ;       , "auth" := auth
  ;       })
  ;     (with-read 'final accounts acct
  ;       { "balance" := final-balance })

  ;     (if
  ;       (and
  ;         (>= initial-balance amount)
  ;         (= ks auth))
  ;       (= final-balance (- initial-balance amount))
  ;       (= final-balance initial-balance)))
  ;   )

  (defun debit (acct amount date data)
    "Debit AMOUNT from ACCT balance recording DATE and DATA"
    (with-read accounts acct
              { "balance":= balance
              , "auth" := auth
              }
      (check-balance balance amount)
      (update accounts acct
                { "balance": (- balance amount)
                , "amount": (- amount)
                , "date": date
                , "data": data
                }
          )))

  ; (property-of debit
  ;   (let
  ;     (with-read 'initial accounts acct
  ;       { "balance" := initial-balance })
  ;     (with-read 'final accounts acct
  ;       { "balance" := final-balance })

  ;     (= final-balance (+ initial-balance amount))
  ;   ))

  ; ; alternately
  ; (property-of debit
  ;   (with-read 'delta accounts acct
  ;     { "balance" := amount }))

 (defun credit (acct amount date data)
   "Credit AMOUNT to ACCT balance recording DATE and DATA"
   (with-read accounts acct
              { "balance":= balance }
     (update accounts acct
            { "balance": (+ balance amount)
            , "amount": amount
            , "date": date
            , "data": data
            }
      )))

  (defconst PACT_REF "ref")





  (defconst ESCROW_ACCT "escrow-account")

  (defun get-pact-account (pfx:string) (format "{}-{}" [pfx (pact-id)]))

  (defun new-pact-account (pfx ccy)
    (let ((a (get-pact-account pfx)))
      (insert accounts a
        { "balance": 0.0
        , "amount": 0.0
        , "ccy": ccy
        , "auth": (format "%s" [(pact-id)])
        , "date": 0
        , "data": "Created pact account"
        }
      )
      a))


)

(create-table accounts)
;done
