# x11kblock
Lock keyboard by timeout.

## Usage

```text
Usage: x11kblock.pl options:
  -t=MINUTES (timeout)
  -l (lock after start)
  -b[=cmd] (blank screen after lock, default: 'xset dpms force off')
  -i=PREFIX (icons: i/lock/PREFIX.png, i/unlock/PREFIX.png)
```

## Also

* send `SIGUSR1` to lock keyboard
* send `SIGUSR2` to unlock keyboard
* send `SIGHUP` to switch locking

## Thanks to

* [xtrlock](https://salsa.debian.org/debian/xtrlock)
* All [CPAN](https://metacpan.org) authors
