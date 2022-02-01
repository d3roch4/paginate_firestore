import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

part 'pagination_state.dart';

class PaginationCubit extends Cubit<PaginationState> {
  PaginationCubit(
    this._query,
    this._limit,
    this._startAfterDocument, {
    this.isLive = false,
    this.sourceStrategy = SourceStrategy.serverElseCache,
  }) : super(PaginationInitial());

  final SourceStrategy sourceStrategy;
  DocumentSnapshot? _lastDocument;
  final int _limit;
  final Query _query;
  final DocumentSnapshot? _startAfterDocument;
  final bool isLive;

  final _streams = <StreamSubscription<QuerySnapshot>>[];

  void filterPaginatedList(String searchTerm) {
    if (state is PaginationLoaded) {
      final loadedState = state as PaginationLoaded;

      final filteredList = loadedState.documentSnapshots
          .where((document) => document
              .data()
              .toString()
              .toLowerCase()
              .contains(searchTerm.toLowerCase()))
          .toList();

      emit(loadedState.copyWith(
        documentSnapshots: filteredList,
        hasReachedEnd: loadedState.hasReachedEnd,
      ));
    }
  }

  void refreshPaginatedList() async {
    _lastDocument = null;
    final localQuery = _getQuery();
    if (isLive) {
      final listener = localQuery.snapshots().listen((querySnapshot) {
        _emitPaginatedState(querySnapshot.docs);
      });

      _streams.add(listener);
    } else {
      final querySnapshot = await _getLocalQuery(localQuery);
      _emitPaginatedState(querySnapshot.docs);
    }
  }

  _getLocalQuery<T>(Query query) async {
    switch(sourceStrategy){
      case SourceStrategy.serverElseCache:
        return query.get(GetOptions(source: Source.serverAndCache));
      case SourceStrategy.cacheElseServer:
        var get = await query.get(GetOptions(source: Source.cache));
        if(get.size==0)
          get = await query.get(GetOptions(source: Source.server));
        return get;
      case SourceStrategy.serverOnly:
        return query.get(GetOptions(source: Source.server));
      case SourceStrategy.cacheOnly:
        return query.get(GetOptions(source: Source.cache));
      default:
        return query.get();
    }
  }

  void fetchPaginatedList() {
    isLive ? _getLiveDocuments() : _getDocuments();
  }

  _getDocuments() async {
    final localQuery = _getQuery();
    try {
      if (state is PaginationInitial) {
        refreshPaginatedList();
      } else if (state is PaginationLoaded) {
        final loadedState = state as PaginationLoaded;
        if (loadedState.hasReachedEnd) return;
        final querySnapshot = await _getLocalQuery(localQuery);
        _emitPaginatedState(
          querySnapshot.docs,
          previousList:
              loadedState.documentSnapshots as List<QueryDocumentSnapshot>,
        );
      }
    } on PlatformException catch (exception) {
      print(exception);
      rethrow;
    }
  }

  _getLiveDocuments() {
    final localQuery = _getQuery();
    if (state is PaginationInitial) {
      refreshPaginatedList();
    } else if (state is PaginationLoaded) {
      final loadedState = state as PaginationLoaded;
      if (loadedState.hasReachedEnd) return;
      final listener = localQuery.snapshots().listen((querySnapshot) {
        _emitPaginatedState(
          querySnapshot.docs,
          previousList:
              loadedState.documentSnapshots as List<QueryDocumentSnapshot>,
        );
      });

      _streams.add(listener);
    }
  }

  void _emitPaginatedState(
    List<QueryDocumentSnapshot> newList, {
    List<QueryDocumentSnapshot> previousList = const [],
  }) {
    _lastDocument = newList.isNotEmpty ? newList.last : null;
    emit(PaginationLoaded(
      documentSnapshots: _mergeSnapshots(previousList, newList),
      hasReachedEnd: newList.isEmpty,
    ));
  }

  List<QueryDocumentSnapshot> _mergeSnapshots(
    List<QueryDocumentSnapshot> previousList,
    List<QueryDocumentSnapshot> newList,
  ) {
    final prevIds = previousList.map((prevSnapshot) => prevSnapshot.id).toSet();
    newList.retainWhere((newSnapshot) => prevIds.add(newSnapshot.id));
    return previousList + newList;
  }

  Query _getQuery() {
    var localQuery = (_lastDocument != null)
        ? _query.startAfterDocument(_lastDocument!)
        : _startAfterDocument != null
            ? _query.startAfterDocument(_startAfterDocument!)
            : _query;
    localQuery = localQuery.limit(_limit);
    return localQuery;
  }

  void dispose() {
    for (var listener in _streams) {
      listener.cancel();
    }
  }
}

enum SourceStrategy {
  serverOnly,
  cacheOnly,
  serverElseCache,
  cacheElseServer,
}
